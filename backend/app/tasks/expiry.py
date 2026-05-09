"""
Background scheduler – runs periodically to expire/auto-complete orders
and broadcast WebSocket events.
"""
import logging
import uuid

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select, text

from app.core.fcm import send_push
from app.core.redis import publish_event
from app.database import SessionLocal
from app.models.user import DeviceToken

logger = logging.getLogger(__name__)

scheduler = AsyncIOScheduler(timezone="UTC")


async def _push(db, user_id: uuid.UUID, title: str, body: str, order_id) -> None:
    try:
        result = await db.execute(select(DeviceToken).where(DeviceToken.user_id == user_id))
        tokens = [r.token for r in result.scalars().all()]
        await send_push(tokens, title, body, {"order_id": str(order_id)})
    except Exception as e:
        logger.error("FCM push failed for user %s: %s", user_id, e)


@scheduler.scheduled_job("interval", minutes=1, id="expire_orders", max_instances=1)
async def expire_orders_job() -> None:
    async with SessionLocal() as db:
        try:
            result = await db.execute(text("SELECT * FROM fn_expire_pending_orders()"))
            rows = result.fetchall()

            # Collect data needed for notifications BEFORE any async/commit
            pending_notifications: list[tuple[uuid.UUID, uuid.UUID]] = []  # (creator_id, order_id)
            order_ids = []

            for row in rows:
                order_id, creator_id, _gold_reward = row
                logger.info("Expiring order %s (creator=%s)", order_id, creator_id)
                order_ids.append(order_id)
                pending_notifications.append((creator_id, order_id))

                await publish_event("order_expired", {"order_id": str(order_id)})

            if order_ids:
                await db.commit()
                logger.info("Expired %d orders (kept in DB for archival)", len(order_ids))

                for creator_id, order_id in pending_notifications:
                    await _push(db, creator_id, "Đơn hàng đã hết hạn", "Đơn không có shipper nhận.", order_id)

        except Exception as e:
            await db.rollback()
            logger.exception("expire_orders_job failed: %s", e)



@scheduler.scheduled_job("interval", minutes=5, id="autocomplete_accepted", max_instances=1)
async def autocomplete_accepted_job() -> None:
    async with SessionLocal() as db:
        try:
            result = await db.execute(text("SELECT * FROM fn_autocomplete_accepted_orders()"))
            rows = result.fetchall()

            pending_notifications: list[tuple] = []

            for row in rows:
                order_id, shipper_id, creator_id, _gold_reward = row
                logger.info("Auto-completing accepted order %s (shipper=%s)", order_id, shipper_id)

                await publish_event("order_completed", {"order_id": str(order_id)})
                pending_notifications.append((creator_id, shipper_id, order_id))

            if rows:
                await db.commit()
                logger.info("Auto-completed %d accepted orders", len(rows))

                for creator_id, shipper_id, order_id in pending_notifications:
                    await _push(db, shipper_id, "Đơn hoàn thành tự động!", "Đơn đã được tự động xác nhận", order_id)
                    if creator_id:
                        await _push(db, creator_id, "Đơn hàng đã hoàn thành", "Đơn được tự động xác nhận do shipper không nhận phản hồi", order_id)

        except Exception as e:
            await db.rollback()
            logger.exception("autocomplete_accepted_job failed: %s", e)


_CLEANUP_SQL = text("""
WITH
del_refresh AS (
    DELETE FROM refresh_tokens
    WHERE expires_at < NOW() - INTERVAL '90 days'
       OR (revoked = TRUE AND created_at < NOW() - INTERVAL '7 days')
    RETURNING id
),
del_notifications AS (
    DELETE FROM notifications
    WHERE is_read = TRUE
      AND created_at < NOW() - INTERVAL '90 days'
    RETURNING id
)
SELECT
    (SELECT count(*) FROM del_refresh)       AS refresh_deleted,
    (SELECT count(*) FROM del_notifications) AS notif_deleted;
""")


@scheduler.scheduled_job("interval", weeks=1, id="cleanup_stale_data", max_instances=1)
async def cleanup_stale_data_job() -> None:
    async with SessionLocal() as db:
        try:
            result = await db.execute(_CLEANUP_SQL)
            row = result.fetchone()
            refresh_deleted = row.refresh_deleted if row else 0
            notif_deleted = row.notif_deleted if row else 0
            await db.commit()
            logger.info(
                "cleanup_stale_data_job: refresh_tokens deleted=%d notifications deleted=%d",
                refresh_deleted, notif_deleted,
            )
        except Exception as e:
            await db.rollback()
            logger.exception("cleanup_stale_data_job failed: %s", e)


_ARCHIVE_STATUSES = ("expired", "completed", "cancelled")

_ARCHIVE_SQL = text("""
WITH archived AS (
    INSERT INTO order_history (
        id, creator_id, shipper_id, note, gold_reward,
        ship_apartment_id, ship_location, ship_building, ship_floor, ship_room,
        validity_option, expires_at, status,
        created_at, updated_at, accepted_at, delivering_at, completed_at,
        cancelled_at, estimated_minutes, estimated_delivery_at,
        images, archived_at
    )
    SELECT
        o.id, o.creator_id, o.shipper_id, o.note, o.gold_reward,
        o.ship_apartment_id, o.ship_location, o.ship_building, o.ship_floor, o.ship_room,
        o.validity_option, o.expires_at, o.status,
        o.created_at, o.updated_at, o.accepted_at, o.delivering_at, o.completed_at,
        o.cancelled_at, o.estimated_minutes, o.estimated_delivery_at,
        COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'id',          oi.id,
                    'storage_key', oi.storage_key,
                    'public_url',  oi.public_url,
                    'sort_order',  oi.sort_order
                ) ORDER BY oi.sort_order
            )
            FROM order_images oi WHERE oi.order_id = o.id),
            '[]'::jsonb
        ),
        NOW()
    FROM orders o
    WHERE o.status = ANY(:statuses)
      AND o.updated_at < NOW() - INTERVAL '48 hours'
    ON CONFLICT (id) DO NOTHING
    RETURNING id
),
deleted AS (
    DELETE FROM orders WHERE id IN (SELECT id FROM archived)
    RETURNING id
)
SELECT
    (SELECT count(*) FROM archived) AS inserted,
    (SELECT count(*) FROM deleted)  AS deleted;
""")


@scheduler.scheduled_job("interval", hours=48, id="archive_orders", max_instances=1)
async def archive_orders_job() -> None:
    async with SessionLocal() as db:
        try:
            result = await db.execute(
                _ARCHIVE_SQL,
                {"statuses": list(_ARCHIVE_STATUSES)},
            )
            row = result.fetchone()
            inserted, deleted = (row.inserted, row.deleted) if row else (0, 0)
            await db.commit()
            logger.info("archive_orders_job: inserted=%d deleted=%d", inserted, deleted)
        except Exception as e:
            await db.rollback()
            logger.exception("archive_orders_job failed: %s", e)


def start_scheduler() -> None:
    if not scheduler.running:
        scheduler.start()
        logger.info("Order expiry scheduler started (interval=30s)")


def stop_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
