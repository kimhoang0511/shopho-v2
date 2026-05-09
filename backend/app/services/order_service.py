"""
Core business logic for orders.
All writes use SELECT ... FOR UPDATE to prevent race conditions at scale.
"""
import asyncio
import logging
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.redis import cache_delete, publish_event
from app.models.order import Order, OrderImage, OrderStatus, ShipLocationType, VALIDITY_OPTIONS
from app.models.user import DeviceToken, ShipperAlert, ShipperAlertLocation, User
from app.core.fcm import send_push, prune_stale_tokens
from app.schemas.order import OrderCreate, OrderListItem, OrderResponse

logger = logging.getLogger(__name__)


async def _push_new_order_alerts(
    *,
    order_id: uuid.UUID,
    ship_apartment_id: uuid.UUID | None,
    ship_building: str | None,
    ship_floor: int | None,
    creator_id: uuid.UUID,
    note: str,
    gold_reward: float,
) -> None:
    """Background task: FCM push to shippers whose location filter matches this order.

    Single 3-way JOIN (locations → alerts → device_tokens) = one DB round-trip.
    idx_sal_apt_building(apartment_id, building) limits the scan to rows for
    this apartment only, so query cost scales with shippers-per-apt, not total users.
    """
    if ship_apartment_id is None:
        return

    from app.database import SessionLocal

    await asyncio.sleep(0.2)
    try:
        async with SessionLocal() as db:
            rows = await db.execute(
                select(DeviceToken.token)
                .join(ShipperAlertLocation, ShipperAlertLocation.user_id == DeviceToken.user_id)
                .join(ShipperAlert, ShipperAlert.user_id == ShipperAlertLocation.user_id)
                .where(
                    ShipperAlertLocation.apartment_id == ship_apartment_id,
                    or_(ShipperAlertLocation.building.is_(None),
                        ShipperAlertLocation.building == ship_building),
                    or_(ShipperAlertLocation.floor.is_(None),
                        ShipperAlertLocation.floor == ship_floor),
                    ShipperAlert.enabled.is_(True),
                    ShipperAlert.user_id != creator_id,
                    or_(ShipperAlert.min_gold.is_(None),
                        ShipperAlert.min_gold <= gold_reward),
                )
                .distinct()
            )
            tokens = list(rows.scalars().all())
            if tokens:
                stale = await send_push(
                    tokens,
                    "Có đơn hàng mới!",
                    f"{gold_reward:.0f}K · {note[:60]}",
                    {"order_id": str(order_id), "type": "new_order"},
                )
                await prune_stale_tokens(db, stale)
    except Exception as exc:
        logger.error("_push_new_order_alerts failed: %s", exc)


class OrderError(Exception):
    def __init__(self, detail: str, status_code: int = 400):
        self.detail = detail
        self.status_code = status_code


# ─── helpers ────────────────────────────────────────────────

async def _push(db: AsyncSession, user_id: uuid.UUID, title: str, body: str, order_id: uuid.UUID) -> None:
    result = await db.execute(select(DeviceToken).where(DeviceToken.user_id == user_id))
    tokens = [row.token for row in result.scalars().all()]
    stale = await send_push(tokens, title, body, {"order_id": str(order_id)})
    await prune_stale_tokens(db, stale)

def _calc_expires(validity_option: str) -> datetime:
    minutes = VALIDITY_OPTIONS[validity_option]
    return datetime.now(timezone.utc) + timedelta(minutes=minutes)


async def _get_order_or_404(db: AsyncSession, order_id: uuid.UUID) -> Order:
    order = await db.scalar(
        select(Order)
        .options(selectinload(Order.images), selectinload(Order.creator), selectinload(Order.shipper))
        .where(Order.id == order_id)
    )
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    return order


async def _invalidate_order_cache() -> None:
    await cache_delete("shopho:orders:pending:list")


# ─── CREATE ─────────────────────────────────────────────────

async def create_order(
    db: AsyncSession,
    creator: User,
    data: OrderCreate,
    image_keys: list[tuple[str, str]],   # [(storage_key, public_url), ...]
) -> Order:
    # Validate location fields
    if data.ship_location in (ShipLocationType.floor, ShipLocationType.room):
        if data.ship_floor is None:
            raise OrderError("Cần nhập tầng cho vị trí ship này")
    if data.ship_location == ShipLocationType.room:
        if not data.ship_room:
            raise OrderError("Cần nhập số phòng cho vị trí ship này")

    if creator.order_slots <= 0:
        raise OrderError("Bạn đã hết lượt tạo đơn. Vui lòng nạp thêm lượt để tiếp tục.", 403)
    creator.order_slots -= 1
    db.add(creator)

    order = Order(
        creator_id=creator.id,
        note=data.note,
        gold_reward=data.gold_reward,
        ship_apartment_id=creator.apartment_id,
        ship_location=data.ship_location,
        ship_building=data.ship_building,
        ship_floor=data.ship_floor,
        ship_room=data.ship_room,
        validity_option=data.validity_option,
        expires_at=_calc_expires(data.validity_option),
        status=OrderStatus.pending,
    )
    db.add(order)
    await db.flush()   # get order.id

    # Attach images
    for idx, (key, url) in enumerate(image_keys):
        db.add(OrderImage(order_id=order.id, storage_key=key, public_url=url, sort_order=idx))

    await db.flush()

    # Broadcast new order event to all listening shippers
    await publish_event("order_created", {
        "order_id": str(order.id),
        "note": order.note,
        "gold_reward": float(order.gold_reward),
        "ship_building": order.ship_building,
        "ship_location": order.ship_location.value,
        "ship_apartment_id": str(order.ship_apartment_id) if order.ship_apartment_id else None,
    })
    await _invalidate_order_cache()

    # Push FCM to shippers whose browse-alert filter matches this order.
    # Runs in background after commit so it doesn't delay the response.
    asyncio.create_task(
        _push_new_order_alerts(
            order_id=order.id,
            ship_apartment_id=order.ship_apartment_id,
            ship_building=order.ship_building,
            ship_floor=order.ship_floor,
            creator_id=creator.id,
            note=order.note,
            gold_reward=float(order.gold_reward),
        )
    )

    # Reload with relationships so FastAPI can serialize without lazy-load errors
    return await _get_order_or_404(db, order.id)


# ─── LIST (shippers browsing) ────────────────────────────────

async def list_pending_orders(
    db: AsyncSession,
    apartment_ids: list[uuid.UUID] | None = None,
    building_pairs: list[tuple[uuid.UUID, str]] | None = None,
    floors: list[int] | None = None,
    limit: int = 50,
    offset: int = 0,
) -> list[Order]:
    now = datetime.now(timezone.utc)
    q = (
        select(Order)
        .options(selectinload(Order.images), selectinload(Order.creator))
        .where(Order.status == OrderStatus.pending, Order.expires_at > now)
        .order_by(Order.created_at.desc())
        .limit(limit)
        .offset(offset)
    )

    conditions = []
    if apartment_ids:
        conditions.append(Order.ship_apartment_id.in_(apartment_ids))
    if building_pairs:
        for apt_id, building in building_pairs:
            conditions.append(
                (Order.ship_apartment_id == apt_id) & (Order.ship_building == building)
            )
    if conditions:
        q = q.where(or_(*conditions))

    if floors:
        # Include lobby-only orders (ship_location=building) alongside floor matches
        q = q.where(
            or_(
                Order.ship_floor.in_(floors),
                Order.ship_location == ShipLocationType.building,
            )
        )

    result = await db.execute(q)
    return list(result.scalars().all())


# ─── UPDATE ─────────────────────────────────────────────────

async def update_order(
    db: AsyncSession,
    user: User,
    order_id: uuid.UUID,
    note: str,
    gold_reward: float,
    ship_location: ShipLocationType,
    validity_option: str,
    image_keys: list[tuple[str, str]] | None,  # None = keep existing
) -> Order:
    from sqlalchemy import delete as sa_delete

    order = await db.scalar(
        select(Order).where(Order.id == order_id).with_for_update()
    )
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.creator_id != user.id:
        raise OrderError("Bạn không có quyền sửa đơn này", 403)
    if order.status != OrderStatus.pending:
        raise OrderError("Chỉ có thể sửa đơn đang ở trạng thái chờ", 400)

    order.note = note.strip()
    order.ship_location = ship_location

    if validity_option != order.validity_option:
        order.validity_option = validity_option
        order.expires_at = _calc_expires(validity_option)

    if gold_reward != float(order.gold_reward):
        order.gold_reward = gold_reward

    if image_keys is not None:
        await db.execute(sa_delete(OrderImage).where(OrderImage.order_id == order.id))
        for idx, (key, url) in enumerate(image_keys):
            db.add(OrderImage(order_id=order.id, storage_key=key, public_url=url, sort_order=idx))

    await db.flush()
    await _invalidate_order_cache()

    asyncio.create_task(
        _push_new_order_alerts(
            order_id=order.id,
            ship_apartment_id=order.ship_apartment_id,
            ship_building=order.ship_building,
            ship_floor=order.ship_floor,
            creator_id=order.creator_id,
            note=order.note,
            gold_reward=float(order.gold_reward),
        )
    )

    return await _get_order_or_404(db, order.id)


# ─── ACCEPT ─────────────────────────────────────────────────

async def accept_order(db: AsyncSession, shipper: User, order_id: uuid.UUID, estimated_minutes: int | None = None) -> tuple[Order, float]:
    """
    Race-condition safe: uses SELECT FOR UPDATE then checks status.
    Only the first shipper wins; subsequent calls raise OrderError.
    """
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(Order)
        .where(Order.id == order_id)
        .with_for_update(skip_locked=True)   # non-blocking; losers get nothing
    )
    order = result.scalar_one_or_none()

    if not order:
        raise OrderError("Đơn đã được nhận bởi người khác, vui lòng chọn đơn khác", 409)
    if order.status != OrderStatus.pending:
        raise OrderError("Đơn không còn ở trạng thái chờ", 409)
    if order.expires_at <= now:
        raise OrderError("Đơn đã hết hiệu lực", 410)
    if order.creator_id == shipper.id:
        raise OrderError("Bạn không thể nhận đơn của chính mình", 400)
    if shipper.order_slots <= 0:
        raise OrderError("Bạn đã hết lượt nhận đơn. Vui lòng nạp thêm lượt để tiếp tục.", 403)

    shipper.order_slots -= 1
    db.add(shipper)
    order.status = OrderStatus.accepted
    order.shipper_id = shipper.id
    order.accepted_at = now
    order.estimated_minutes = estimated_minutes
    if estimated_minutes is not None:
        order.estimated_delivery_at = now + timedelta(minutes=estimated_minutes)

    await db.flush()

    await publish_event("order_accepted", {
        "order_id": str(order.id),
        "shipper_id": str(shipper.id),
    })
    await _invalidate_order_cache()
    await _push(db, order.creator_id, "Đơn hàng đã được nhận", f"{shipper.display_name or shipper.username} đã nhận đơn của bạn", order.id)

    return await _get_order_or_404(db, order.id)


# ─── SHIPPER: CONFIRM DELIVERY ───────────────────────────────

async def shipper_confirm_delivery(
    db: AsyncSession,
    shipper: User,
    order_id: uuid.UUID,
    adjusted_gold: float | None = None,
    total_gold: float | None = None,
) -> Order:
    order = await db.scalar(
        select(Order).where(Order.id == order_id).with_for_update()
    )
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.shipper_id != shipper.id:
        raise OrderError("Bạn không phải shipper của đơn này", 403)
    if order.status != OrderStatus.accepted:
        raise OrderError("Chỉ có thể xác nhận giao từ trạng thái 'đã nhận'", 400)

    if adjusted_gold is not None:
        original = float(order.gold_reward)
        if adjusted_gold < 2:
            raise OrderError("Phí tối thiểu là 2", 400)
        if adjusted_gold > original:
            raise OrderError("Không thể tăng phí khi xác nhận giao", 400)
        if adjusted_gold < original:
            order.gold_reward = adjusted_gold

    if total_gold is not None:
        if total_gold < float(order.gold_reward):
            raise OrderError("Tổng tiền phải lớn hơn hoặc bằng tiền công mua/ship", 400)
        order.total_gold = total_gold

    now = datetime.now(timezone.utc)
    order.status = OrderStatus.completed
    order.completed_at = now
    shipper_id = order.shipper_id
    gold_amount = float(order.gold_reward)
    await db.flush()

    from app.services.gold_service import reward_shipper
    await reward_shipper(db, shipper_id, order.id, gold_amount)

    await publish_event("order_completed", {"order_id": str(order.id)})
    await _push(db, order.creator_id, "Đơn hàng đã hoàn thành", "Shipper đã xác nhận giao hàng thành công", order.id)
    return await _get_order_or_404(db, order.id)



# ─── SHIPPER: CANCEL ACCEPTED/DELIVERING ─────────────────────

async def shipper_cancel_order(db: AsyncSession, shipper: User, order_id: uuid.UUID) -> Order:
    order = await db.scalar(
        select(Order).where(Order.id == order_id).with_for_update()
    )
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.shipper_id != shipper.id:
        raise OrderError("Bạn không phải shipper của đơn này", 403)
    if order.status != OrderStatus.accepted:
        raise OrderError("Chỉ có thể huỷ đơn đang ở trạng thái 'đã nhận'", 400)

    now = datetime.now(timezone.utc)
    still_valid = order.expires_at > now

    creator_id = order.creator_id
    if still_valid:
        # Reopen the order so another shipper can pick it up
        order.status = OrderStatus.pending
        order.shipper_id = None
        order.accepted_at = None
        order.estimated_minutes = None
        order.estimated_delivery_at = None
        await db.flush()
        await publish_event("order_reopened", {"order_id": str(order.id)})
    else:
        order.status = OrderStatus.cancelled
        order.cancelled_at = now
        await db.flush()
        await publish_event("order_cancelled", {"order_id": str(order.id)})

    await _invalidate_order_cache()
    await _push(db, creator_id, "Shipper đã huỷ đơn", "Đơn của bạn đã được mở lại để shipper khác nhận", order.id)
    return await _get_order_or_404(db, order.id)


# ─── COMPLETE (creator confirms receipt) ─────────────────────

async def complete_order(
    db: AsyncSession,
    user: User,
    order_id: uuid.UUID,
    bonus_gold: float | None = None,
) -> Order:
    order = await db.scalar(
        select(Order).where(Order.id == order_id).with_for_update()
    )
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.creator_id != user.id:
        raise OrderError("Chỉ người tạo đơn mới có thể xác nhận hoàn thành", 403)
    if order.status != OrderStatus.accepted:
        raise OrderError("Chỉ có thể hoàn thành đơn đang ở trạng thái 'đã nhận'", 400)

    order.status = OrderStatus.completed
    order.completed_at = datetime.now(timezone.utc)

    if bonus_gold and bonus_gold > 0:
        order.gold_reward = float(order.gold_reward) + bonus_gold

    shipper_id = order.shipper_id
    await db.flush()
    await publish_event("order_completed", {"order_id": str(order.id)})
    await _push(db, shipper_id, "Đơn hoàn thành!", "Người đặt đã xác nhận hoàn thành đơn", order.id)
    return await _get_order_or_404(db, order.id)



# ─── CANCEL ─────────────────────────────────────────────────

async def cancel_order(db: AsyncSession, user: User, order_id: uuid.UUID) -> Order:
    order = await db.scalar(
        select(Order).where(Order.id == order_id).with_for_update()
    )
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.creator_id != user.id:
        raise OrderError("Chỉ người tạo mới có thể huỷ đơn", 403)

    now = datetime.now(timezone.utc)

    shipper_id: uuid.UUID | None = None

    if order.status == OrderStatus.pending:
        order.status = OrderStatus.cancelled
        order.cancelled_at = now

    elif order.status == OrderStatus.accepted:
        # Allow creator to cancel within 10 minutes of acceptance
        if order.accepted_at is None or (now - order.accepted_at).total_seconds() > 600:
            raise OrderError("Chỉ có thể huỷ đơn đã nhận trong vòng 10 phút đầu", 400)
        shipper_id = order.shipper_id
        order.status = OrderStatus.cancelled
        order.cancelled_at = now

    else:
        raise OrderError("Không thể huỷ đơn ở trạng thái hiện tại", 400)

    await db.flush()
    await publish_event("order_cancelled", {"order_id": str(order.id)})
    await _invalidate_order_cache()
    if shipper_id:
        await _push(db, shipper_id, "Đơn hàng bị huỷ", "Người đặt đã huỷ đơn bạn đang nhận.", order.id)
    return await _get_order_or_404(db, order.id)


# ─── GOLD PROPOSALS ─────────────────────────────────────────────────────────

async def propose_gold(
    db: AsyncSession,
    user: User,
    order_id: uuid.UUID,
    proposed_gold: float,
) -> "GoldProposal":  # type: ignore[name-defined]
    from sqlalchemy.dialects.postgresql import insert as pg_insert
    from app.models.gold_proposal import GoldProposal

    order = await db.scalar(select(Order).where(Order.id == order_id))
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.status != OrderStatus.pending:
        raise OrderError("Chỉ có thể đề nghị trên đơn đang chờ tiếp nhận", 400)
    if order.creator_id == user.id:
        raise OrderError("Không thể đề nghị trên đơn của chính mình", 400)
    if proposed_gold <= float(order.gold_reward):
        raise OrderError(f"Mức đề nghị phải cao hơn {float(order.gold_reward)} Gold", 400)

    stmt = (
        pg_insert(GoldProposal)
        .values(order_id=order_id, proposer_id=user.id, proposed_gold=proposed_gold)
        .on_conflict_do_update(
            constraint="uq_gold_proposal_order_proposer",
            set_={"proposed_gold": proposed_gold, "created_at": datetime.now(timezone.utc)},
        )
        .returning(GoldProposal.id)
    )
    result = await db.execute(stmt)
    proposal_id = result.scalar_one()
    await db.commit()

    proposal = await db.scalar(
        select(GoldProposal)
        .where(GoldProposal.id == proposal_id)
        .options(selectinload(GoldProposal.proposer))
    )

    proposer_name = proposal.proposer.display_name or proposal.proposer.username
    await _push(
        db,
        order.creator_id,
        "Shipper đề nghị tăng tiền!",
        f"{proposer_name} đề nghị tăng lên {proposed_gold:.0f}K cho đơn của bạn",
        order.id,
    )

    return proposal


async def list_proposals(
    db: AsyncSession,
    user: User,
    order_id: uuid.UUID,
) -> list["GoldProposal"]:  # type: ignore[name-defined]
    from app.models.gold_proposal import GoldProposal

    order = await db.scalar(select(Order).where(Order.id == order_id))
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.creator_id != user.id:
        raise OrderError("Chỉ người tạo đơn mới xem được đề nghị", 403)

    result = await db.execute(
        select(GoldProposal)
        .where(GoldProposal.order_id == order_id)
        .options(selectinload(GoldProposal.proposer))
        .order_by(GoldProposal.proposed_gold.desc())
    )
    return list(result.scalars().all())


# ─── RENEW (creator re-activates expired order) ──────────────

async def renew_order(
    db: AsyncSession,
    user: User,
    order_id: uuid.UUID,
) -> Order:
    order = await db.scalar(
        select(Order).where(Order.id == order_id).with_for_update()
    )
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.creator_id != user.id:
        raise OrderError("Chỉ người tạo đơn mới có thể đặt lại", 403)
    if order.status != OrderStatus.expired:
        raise OrderError("Chỉ có thể đặt lại đơn đã hết hạn", 400)

    order.status = OrderStatus.pending
    order.expires_at = _calc_expires(order.validity_option)
    await db.flush()
    await _invalidate_order_cache()
    await publish_event("order_renewed", {"order_id": str(order.id)})
    return await _get_order_or_404(db, order.id)


async def accept_gold_proposal(
    db: AsyncSession,
    user: User,
    order_id: uuid.UUID,
    proposal_id: uuid.UUID,
) -> Order:
    from sqlalchemy import delete
    from app.models.gold_proposal import GoldProposal

    order = await db.scalar(
        select(Order).where(Order.id == order_id).with_for_update()
    )
    if not order:
        raise OrderError("Đơn không tồn tại", 404)
    if order.creator_id != user.id:
        raise OrderError("Chỉ người tạo đơn mới chấp nhận được đề nghị", 403)
    if order.status != OrderStatus.pending:
        raise OrderError("Chỉ chấp nhận đề nghị trên đơn đang chờ tiếp nhận", 400)

    proposal = await db.scalar(
        select(GoldProposal).where(
            GoldProposal.id == proposal_id,
            GoldProposal.order_id == order_id,
        )
    )
    if not proposal:
        raise OrderError("Không tìm thấy đề nghị", 404)

    new_gold = float(proposal.proposed_gold)
    proposer_id = proposal.proposer_id  # capture before bulk-delete below

    order.gold_reward = new_gold

    await db.execute(delete(GoldProposal).where(GoldProposal.order_id == order_id))
    await db.flush()
    await _invalidate_order_cache()

    updated_order = await _get_order_or_404(db, order.id)
    await _push(
        db,
        proposer_id,
        "Đề nghị tiền được chấp nhận!",
        f"Người đặt chấp nhận mức {new_gold:.0f}K của bạn. Hãy vào nhận đơn ngay!",
        order.id,
    )
    return updated_order
