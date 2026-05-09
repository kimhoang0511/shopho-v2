import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
import logging
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import current_user
from app.database import get_db
from app.models.order import ShipLocationType
from app.models.user import User
from app.schemas.order import AcceptOrderBody, AcceptOrderResponse, CompleteOrderBody, DeliverOrderBody, GoldProposalResponse, MarketPriceItem, OrderCreate, OrderListItem, OrderResponse, ProposeGoldBody
from app.services.order_service import OrderError, accept_gold_proposal, accept_order, cancel_order, complete_order, create_order, list_pending_orders, list_proposals, propose_gold, renew_order, shipper_cancel_order, shipper_confirm_delivery, update_order
from app.services.storage_service import upload_image

router = APIRouter(prefix="/orders", tags=["orders"])


def _raise(e: OrderError) -> None:
    raise HTTPException(status_code=e.status_code, detail=e.detail)


# ─── CREATE ─────────────────────────────────────────────────

@router.post("", response_model=OrderResponse, status_code=201)
async def create_order_endpoint(
    note: Annotated[str, Form()],
    gold_reward: Annotated[float, Form()],
    ship_location: Annotated[ShipLocationType, Form()],
    validity_option: Annotated[str, Form()],
    ship_building: Annotated[str | None, Form()] = None,
    ship_floor: Annotated[int | None, Form()] = None,
    ship_room: Annotated[str | None, Form()] = None,
    images: list[UploadFile] = File(default=[]),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    data = OrderCreate(
        note=note,
        gold_reward=gold_reward,
        ship_location=ship_location,
        validity_option=validity_option,
        ship_building=ship_building,
        ship_floor=ship_floor,
        ship_room=ship_room,
    )

    # Upload images to MinIO (max 5)
    image_keys: list[tuple[str, str]] = []
    for img in images[:5]:
        try:
            key, url = await upload_image(img)
            image_keys.append((key, url))
        except Exception:
            raise HTTPException(status_code=400, detail="Upload ảnh thất bại")

    try:
        order = await create_order(db, user, data, image_keys)
        return order
    except OrderError as e:
        _raise(e)


# ─── LIST ────────────────────────────────────────────────────

@router.get("", response_model=list[OrderListItem])
async def list_orders_endpoint(
    apartment_ids: list[uuid.UUID] = Query(default=[]),
    building_keys: list[str] = Query(default=[]),
    floors: list[int] = Query(default=[]),
    limit: int = Query(50, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_user),
):
    # building_keys format: "apartment_uuid:building_name"
    building_pairs: list[tuple[uuid.UUID, str]] = []
    for key in building_keys:
        try:
            apt_id_str, building = key.split(":", 1)
            building_pairs.append((uuid.UUID(apt_id_str), building))
        except (ValueError, AttributeError):
            logging.getLogger(__name__).warning("Invalid building_key: %s", key)

    orders = await list_pending_orders(
        db,
        apartment_ids=apartment_ids or None,
        building_pairs=building_pairs or None,
        floors=floors or None,
        limit=limit,
        offset=offset,
    )
    return [
        OrderListItem(
            id=o.id,
            creator_id=o.creator_id,
            note=o.note,
            gold_reward=float(o.gold_reward),
            ship_location=o.ship_location,
            ship_building=o.ship_building,
            ship_floor=o.ship_floor,
            ship_room=o.ship_room,
            expires_at=o.expires_at,
            created_at=o.created_at,
            images=[{"id": i.id, "public_url": i.public_url, "sort_order": i.sort_order} for i in o.images],
            creator_building=o.creator.apt_building if o.creator else None,
            ship_apartment_name=o.ship_apartment.name if o.ship_apartment else None,
        )
        for o in orders
    ]


# ─── UPDATE ─────────────────────────────────────────────────

@router.patch("/{order_id}", response_model=OrderResponse)
async def update_order_endpoint(
    order_id: uuid.UUID,
    note: Annotated[str, Form()],
    gold_reward: Annotated[float, Form()],
    ship_location: Annotated[ShipLocationType, Form()],
    validity_option: Annotated[str, Form()],
    replace_images: Annotated[bool, Form()] = False,
    images: list[UploadFile] = File(default=[]),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    image_keys: list[tuple[str, str]] | None = None
    if replace_images:
        image_keys = []
        for img in images[:1]:
            try:
                key, url = await upload_image(img)
                image_keys.append((key, url))
            except Exception:
                raise HTTPException(status_code=400, detail="Upload ảnh thất bại")

    try:
        return await update_order(
            db, user, order_id,
            note=note,
            gold_reward=gold_reward,
            ship_location=ship_location,
            validity_option=validity_option,
            image_keys=image_keys,
        )
    except OrderError as e:
        _raise(e)


# ─── MARKET PRICES ──────────────────────────────────────────

@router.get("/market-prices", response_model=list[MarketPriceItem])
async def market_prices_endpoint(
    ship_location: ShipLocationType = Query(...),
    ship_apartment_id: uuid.UUID = Query(...),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_user),
):
    from sqlalchemy import select
    from app.models.order import Order, OrderStatus

    # Select only the 5 columns used — avoids loading creator/shipper/images via selectin
    result = await db.execute(
        select(
            Order.ship_location,
            Order.ship_building,
            Order.ship_floor,
            Order.ship_room,
            Order.gold_reward,
        )
        .where(
            Order.ship_apartment_id == ship_apartment_id,
            Order.ship_location == ship_location,
            Order.status.in_([OrderStatus.accepted, OrderStatus.completed]),
        )
        .order_by(Order.created_at.desc())
        .limit(7)
    )
    return [
        MarketPriceItem(
            ship_location=row.ship_location,
            ship_building=row.ship_building,
            ship_floor=row.ship_floor,
            ship_room=row.ship_room,
            gold_reward=float(row.gold_reward),
        )
        for row in result
    ]


# ─── GET BY ID ──────────────────────────────────────────────

@router.get("/{order_id}", response_model=OrderResponse)
async def get_order_endpoint(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_user),
):
    from app.services.order_service import _get_order_or_404
    try:
        return await _get_order_or_404(db, order_id)
    except OrderError as e:
        _raise(e)


# ─── ACCEPT ─────────────────────────────────────────────────

@router.post("/{order_id}/accept", response_model=AcceptOrderResponse)
async def accept_order_endpoint(
    order_id: uuid.UUID,
    body: AcceptOrderBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        order = await accept_order(db, user, order_id, body.estimated_minutes)
        return AcceptOrderResponse(order=order)
    except OrderError as e:
        _raise(e)


# ─── DELIVER (shipper confirms delivery) ─────────────────────

@router.post("/{order_id}/deliver", response_model=OrderResponse)
async def deliver_order_endpoint(
    order_id: uuid.UUID,
    body: DeliverOrderBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        return await shipper_confirm_delivery(db, user, order_id, body.adjusted_gold, body.total_gold)
    except OrderError as e:
        _raise(e)



# ─── SHIPPER CANCEL ──────────────────────────────────────────

@router.post("/{order_id}/shipper-cancel", response_model=OrderResponse)
async def shipper_cancel_endpoint(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        return await shipper_cancel_order(db, user, order_id)
    except OrderError as e:
        _raise(e)


# ─── COMPLETE (creator confirms receipt) ─────────────────────

@router.post("/{order_id}/complete", response_model=OrderResponse)
async def complete_order_endpoint(
    order_id: uuid.UUID,
    body: CompleteOrderBody = CompleteOrderBody(),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        return await complete_order(db, user, order_id, bonus_gold=body.bonus_gold)
    except OrderError as e:
        _raise(e)



# ─── RENEW ──────────────────────────────────────────────────

@router.post("/{order_id}/renew", response_model=OrderResponse)
async def renew_order_endpoint(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        return await renew_order(db, user, order_id)
    except OrderError as e:
        _raise(e)


# ─── CANCEL ─────────────────────────────────────────────────

@router.post("/{order_id}/cancel", response_model=OrderResponse)
async def cancel_order_endpoint(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        return await cancel_order(db, user, order_id)
    except OrderError as e:
        _raise(e)


# ─── GOLD PROPOSALS ─────────────────────────────────────────

@router.post("/{order_id}/propose-gold", response_model=GoldProposalResponse, status_code=201)
async def propose_gold_endpoint(
    order_id: uuid.UUID,
    body: ProposeGoldBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        return await propose_gold(db, user, order_id, body.proposed_gold)
    except OrderError as e:
        _raise(e)


@router.get("/{order_id}/proposals", response_model=list[GoldProposalResponse])
async def list_proposals_endpoint(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        return await list_proposals(db, user, order_id)
    except OrderError as e:
        _raise(e)


@router.post("/{order_id}/proposals/{proposal_id}/accept", response_model=OrderResponse)
async def accept_proposal_endpoint(
    order_id: uuid.UUID,
    proposal_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    try:
        return await accept_gold_proposal(db, user, order_id, proposal_id)
    except OrderError as e:
        _raise(e)


# ─── MY ORDERS ──────────────────────────────────────────────

@router.get("/me/created", response_model=list[OrderResponse])
async def my_created_orders(
    limit: int = Query(20, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    from sqlalchemy import func, select
    from sqlalchemy.orm import selectinload
    from app.models.order import Order, OrderStatus
    from app.models.gold_proposal import GoldProposal

    result = await db.execute(
        select(Order)
        .options(selectinload(Order.images), selectinload(Order.shipper))
        .where(Order.creator_id == user.id)
        .order_by(Order.created_at.desc())
        .limit(limit).offset(offset)
    )
    orders = list(result.scalars().all())

    # Fetch min proposed gold for pending orders in one query
    pending_ids = [o.id for o in orders if o.status == OrderStatus.pending]
    min_gold_map: dict = {}
    if pending_ids:
        rows = await db.execute(
            select(GoldProposal.order_id, func.min(GoldProposal.proposed_gold).label("min_gold"))
            .where(GoldProposal.order_id.in_(pending_ids))
            .group_by(GoldProposal.order_id)
        )
        min_gold_map = {row.order_id: float(row.min_gold) for row in rows}

    return [
        OrderResponse.model_validate(o).model_copy(
            update={"min_proposed_gold": min_gold_map.get(o.id)}
        )
        for o in orders
    ]


@router.get("/me/shipped", response_model=list[OrderResponse])
async def my_shipped_orders(
    limit: int = Query(20, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    from sqlalchemy import select
    from sqlalchemy.orm import selectinload
    from app.models.order import Order

    result = await db.execute(
        select(Order)
        .options(selectinload(Order.images), selectinload(Order.creator))
        .where(Order.shipper_id == user.id)
        .order_by(Order.accepted_at.desc())
        .limit(limit).offset(offset)
    )
    return list(result.scalars().all())
