"""
Chat feature:
  REST  GET  /orders/{id}/messages          — history (last 50)
  REST  GET  /orders/{id}/contact           — counterparty name + phone
  REST  POST /orders/{id}/call              — initiate LiveKit call (sends FCM + returns caller token)
  REST  POST /orders/{id}/livekit-token     — get LiveKit token for recipient after accepting call
  WS        /ws/orders/{id}/chat            — real-time messaging via Redis pub/sub
"""
import asyncio
import json
import logging
import time
import uuid
from datetime import timedelta

import redis.asyncio as aioredis
from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, WebSocket, WebSocketDisconnect
from jose import JWTError
from livekit.api import AccessToken, VideoGrants
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import current_user
from app.config import get_settings
from app.core.limiter import limiter, user_key
from app.core.apns import send_voip_push_multi

from app.core.fcm import send_push, prune_stale_tokens
from app.core.redis import get_redis
from app.core.security import decode_access_token
from app.database import SessionLocal, get_db
from app.models.chat_message import ChatMessage
from app.models.order import Order, OrderStatus
from app.models.user import User, DeviceToken

logger = logging.getLogger(__name__)
router = APIRouter(tags=["chat"])

_ACTIVE_STATUSES = {OrderStatus.accepted, OrderStatus.completed}

_TOKEN_TTL = timedelta(hours=1)



def _chat_channel(order_id: uuid.UUID) -> str:
    return f"shopho:chat:{order_id}"


def _user_channel(user_id: uuid.UUID) -> str:
    return f"shopho:user:{user_id}:events"


def _pending_call_key(user_id: uuid.UUID) -> str:
    return f"shopho:pending_call:{user_id}"


def _pending_missed_call_key(user_id: uuid.UUID) -> str:
    return f"shopho:pending_missed_call:{user_id}"


_CALL_RING_TTL = 45        # seconds — matches the ring timeout on the client side
_MISSED_CALL_TTL = 10 * 60  # 10 minutes — window for B to open app and receive via WS


def _room_name(order_id: uuid.UUID) -> str:
    return f"order-{order_id}"


def _livekit_token(identity: str, display_name: str, room: str) -> str:
    settings = get_settings()
    token = (
        AccessToken(api_key=settings.livekit_api_key, api_secret=settings.livekit_api_secret)
        .with_identity(identity)
        .with_name(display_name)
        .with_grants(VideoGrants(room_join=True, room=room))
        .with_ttl(_TOKEN_TTL)
    )
    return token.to_jwt()


def _fmt(msg: ChatMessage, my_id: uuid.UUID) -> dict:
    return {
        "id": str(msg.id),
        "sender_id": str(msg.sender_id),
        "sender_name": msg.sender.display_name or msg.sender.username if msg.sender else "Ẩn danh",
        "content": msg.content,
        "created_at": msg.created_at.isoformat(),
        "is_me": msg.sender_id == my_id,
    }


# ─── REST: history ──────────────────────────────────────────

@router.get("/orders/{order_id}/messages")
async def get_messages(
    order_id: uuid.UUID,
    limit: int = Query(50, le=100),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    order = await db.scalar(select(Order).where(Order.id == order_id))
    if not order:
        raise HTTPException(404, "Đơn không tồn tại")
    if order.creator_id != user.id and order.shipper_id != user.id:
        raise HTTPException(403, "Không có quyền truy cập")

    result = await db.execute(
        select(ChatMessage)
        .where(ChatMessage.order_id == order_id)
        .order_by(ChatMessage.created_at.asc())
        .limit(limit)
    )
    return [_fmt(m, user.id) for m in result.scalars().all()]


# ─── REST: initiate LiveKit call ─────────────────────────────

@router.post("/orders/{order_id}/call")
@limiter.limit("5/minute", key_func=user_key)
async def initiate_call(
    request: Request,
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    order = await db.scalar(select(Order).where(Order.id == order_id))
    if not order:
        raise HTTPException(404, "Đơn không tồn tại")
    if order.status not in _ACTIVE_STATUSES:
        raise HTTPException(400, "Chỉ có thể gọi khi đơn đang được xử lý")

    if order.creator_id == user.id:
        recipient_id = order.shipper_id
    elif order.shipper_id == user.id:
        recipient_id = order.creator_id
    else:
        raise HTTPException(403, "Không có quyền truy cập")

    if not recipient_id:
        raise HTTPException(404, "Chưa có người tiếp nhận")

    recipient = await db.scalar(select(User).where(User.id == recipient_id))
    if not recipient:
        raise HTTPException(404, "Không tìm thấy người nhận")

    caller_name = user.display_name or user.username
    counterpart_name = recipient.display_name or recipient.username
    room = _room_name(order_id)
    settings = get_settings()
    call_id = str(uuid.uuid4())

    caller_token = _livekit_token(
        identity=f"user-{user.id}",
        display_name=caller_name,
        room=room,
    )

    # Fetch all device tokens for recipient, split by platform
    rows = await db.execute(
        select(DeviceToken.token, DeviceToken.platform)
        .where(DeviceToken.user_id == recipient_id)
    )
    all_tokens = rows.fetchall()

    fcm_tokens  = [r.token for r in all_tokens if r.platform != "ios_voip"]
    voip_tokens = [r.token for r in all_tokens if r.platform == "ios_voip"]

    call_data = {
        "type": "call",
        "call_id": call_id,
        "order_id": str(order_id),
        "caller_id": str(user.id),
        "caller_name": caller_name,
        "livekit_url": settings.livekit_url,
        "room_name": room,
        "initiated_at": int(time.time()),
        "order_note": order.note or "",
    }

    r = await get_redis()

    # Store call in Redis so B can retrieve it when reconnecting WebSocket while
    # A is still ringing. TTL matches client-side ring timeout.
    await r.set(_pending_call_key(recipient_id), json.dumps(call_data), ex=_CALL_RING_TTL)

    # WebSocket (instant, foreground only) — publish before FCM so app-foreground
    # users get it immediately without waiting for FCM delivery.
    await r.publish(_user_channel(recipient_id), json.dumps(call_data))

    # Return the caller token IMMEDIATELY — don't block on FCM/APNs delivery.
    # FCM and VoIP pushes are fire-and-forget: they run in background tasks so
    # the caller's app opens the call screen without waiting for push delivery
    # (which can take 200-500ms+ for APNs HTTP/2 TLS handshake to Apple servers).

    async def _send_pushes() -> None:
        """Fire-and-forget: deliver FCM + VoIP pushes in the background."""
        try:
            stale: list[str] = []
            android_tokens = [r.token for r in all_tokens if r.platform == "android"]
            ios_fcm_tokens = [r.token for r in all_tokens if r.platform not in ("android", "ios_voip")]

            if android_tokens:
                s = await send_push(
                    tokens=android_tokens,
                    title=f"📞 Cuộc gọi từ {caller_name}",
                    body="Nhấn để trả lời",
                    data=call_data,
                    data_only=True,
                    ttl_seconds=40,
                )
                stale.extend(s)

            if ios_fcm_tokens:
                s = await send_push(
                    tokens=ios_fcm_tokens,
                    title=f"Cuộc gọi từ {caller_name}",
                    body="Đang gọi...",
                    data=call_data,
                    data_only=True,
                    ttl_seconds=40,
                )
                stale.extend(s)

            if voip_tokens:
                await send_voip_push_multi(voip_tokens, call_data)

            if stale:
                async with SessionLocal() as db_bg:
                    await prune_stale_tokens(db_bg, stale)
        except Exception:
            logger.exception("Background push delivery failed for call %s", call_id)

    asyncio.create_task(_send_pushes())

    return {
        "call_id": call_id,
        "order_id": str(order_id),
        "counterpart_name": counterpart_name,
        "livekit_url": settings.livekit_url,
        "room_name": room,
        "token": caller_token,
        "order_note": order.note or "",
    }


# ─── REST: get LiveKit token (recipient fallback) ────────────

@router.post("/orders/{order_id}/livekit-token")
async def get_livekit_token(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    """Fallback for recipient to get their LiveKit token if FCM token was missing."""
    order = await db.scalar(select(Order).where(Order.id == order_id))
    if not order:
        raise HTTPException(404, "Đơn không tồn tại")
    if order.creator_id != user.id and order.shipper_id != user.id:
        raise HTTPException(403, "Không có quyền truy cập")
    if order.status not in _ACTIVE_STATUSES:
        raise HTTPException(400, "Chỉ có thể gọi khi đơn đang được xử lý")

    settings = get_settings()
    room = _room_name(order_id)
    display_name = user.display_name or user.username
    token = _livekit_token(
        identity=f"user-{user.id}",
        display_name=display_name,
        room=room,
    )

    # Clear pending-call key so that if the caller later hangs up, the
    # cancel endpoint knows the call was already answered and skips the
    # missed-call notification.
    r = await get_redis()
    await r.delete(_pending_call_key(user.id))

    return {"livekit_url": settings.livekit_url, "room_name": room, "token": token}


# ─── REST: check call status ─────────────────────────────────

@router.get("/calls/{call_id}/status")
async def call_status(
    call_id: str,
    user: User = Depends(current_user),
):
    """Check call status. Returns whether the call is cancelled AND whether
    the recipient has connected. Used by A to detect B's connection state."""
    r = await get_redis()
    cancelled = await r.exists(f"shopho:cancelled_call:{call_id}")
    connected = await r.exists(f"shopho:call_connected:{call_id}")
    return {"cancelled": bool(cancelled), "connected": bool(connected)}


@router.post("/calls/{call_id}/connected")
async def call_connected(
    call_id: str,
    user: User = Depends(current_user),
):
    """Called by B (recipient) after successfully connecting to LiveKit room.
    Stores connected state in Redis and notifies A via WS so A can transition
    from 'connecting' to 'talking' without relying on LiveKit events."""
    r = await get_redis()
    key = f"shopho:call_connected:{call_id}"
    if await r.exists(key):
        return {"ok": True}
    await r.setex(key, _MISSED_CALL_TTL, str(user.id))
    return {"ok": True}


# ─── REST: cancel call ───────────────────────────────────────

@router.post("/orders/{order_id}/call-cancel")
async def cancel_call(
    order_id: uuid.UUID,
    call_id: str = Body(..., embed=True),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    order = await db.scalar(select(Order).where(Order.id == order_id))
    if not order:
        raise HTTPException(404, "Đơn không tồn tại")

    if order.creator_id == user.id:
        recipient_id = order.shipper_id
    elif order.shipper_id == user.id:
        recipient_id = order.creator_id
    else:
        raise HTTPException(403, "Không có quyền truy cập")

    if not recipient_id:
        return {"ok": True}

    rows = await db.execute(
        select(DeviceToken.token, DeviceToken.platform)
        .where(DeviceToken.user_id == recipient_id)
    )
    all_tokens = rows.fetchall()
    fcm_tokens = [r.token for r in all_tokens if r.platform != "ios_voip"]

    cancel_data = {"type": "call_cancel", "call_id": call_id, "order_id": str(order_id)}

    r = await get_redis()

    # Check if recipient's pending call exists and who the caller was.
    # If the current user IS the caller (A hung up / timed out on A's side),
    # send a missed-call notification to B.
    pending_raw = await r.get(_pending_call_key(recipient_id))
    caller_name_for_missed = user.display_name or user.username
    is_caller_cancelling = False
    if pending_raw:
        try:
            pending = json.loads(pending_raw)
            is_caller_cancelling = pending.get("caller_id") == str(user.id)
            caller_name_for_missed = pending.get("caller_name", caller_name_for_missed)
        except Exception:
            pass

    # Remove pending-call entries for both parties.
    await r.delete(_pending_call_key(user.id), _pending_call_key(recipient_id))

    # Mark this call as cancelled so B can check before navigating to call screen
    # (e.g. B accepted from lock screen but A already hung up).
    await r.setex(f"shopho:cancelled_call:{call_id}", _MISSED_CALL_TTL, "1")

    # Send call_cancel so B dismisses the ringing UI (if still showing).
    await r.publish(_user_channel(recipient_id), json.dumps(cancel_data))
    if fcm_tokens:
        stale = await send_push(
            tokens=fcm_tokens,
            title="",
            body="",
            data=cancel_data,
            data_only=True,
        )
        await prune_stale_tokens(db, stale)

    # If A (caller) is cancelling and B hadn't answered → missed call.
    if is_caller_cancelling:
        missed_data = {
            "type": "missed_call",
            "call_id": call_id,
            "order_id": str(order_id),
            "caller_name": caller_name_for_missed,
        }
        missed_json = json.dumps(missed_data)
        # Store in Redis list (max 3) so WS reconnect can deliver all missed calls.
        # LPUSH prepends newest first; LTRIM keeps only the 3 most recent.
        key = _pending_missed_call_key(recipient_id)
        await r.lpush(key, missed_json)
        await r.ltrim(key, 0, 2)
        await r.expire(key, _MISSED_CALL_TTL)
        # FCM: delivers when device wakes up (background/killed). Foreground handled by onMessage.
        if fcm_tokens:
            stale = await send_push(
                tokens=fcm_tokens,
                title=f"Cuộc gọi nhỡ từ {caller_name_for_missed}",
                body="Bạn vừa có một cuộc gọi nhỡ",
                data=missed_data,
            )
            await prune_stale_tokens(db, stale)

    return {"ok": True}


# ─── REST: contact info ──────────────────────────────────────

@router.get("/orders/{order_id}/contact")
async def get_contact(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    order = await db.scalar(select(Order).where(Order.id == order_id))
    if not order:
        raise HTTPException(404, "Đơn không tồn tại")
    if order.status not in _ACTIVE_STATUSES:
        raise HTTPException(400, "Chỉ liên hệ khi đơn đang được xử lý")

    if order.creator_id == user.id:
        counterpart = order.shipper
    elif order.shipper_id == user.id:
        counterpart = order.creator
    else:
        raise HTTPException(403, "Không có quyền truy cập")

    if not counterpart:
        raise HTTPException(404, "Chưa có người tiếp nhận đơn")

    return {
        "id": str(counterpart.id),
        "name": counterpart.display_name or counterpart.username,
        "phone": counterpart.phone,
    }


# ─── WebSocket: real-time chat ───────────────────────────────

@router.websocket("/ws/orders/{order_id}/chat")
async def ws_chat(
    websocket: WebSocket,
    order_id: uuid.UUID,
    token: str = Query(...),
):
    try:
        user_id = uuid.UUID(decode_access_token(token))
    except (JWTError, ValueError):
        await websocket.close(code=4001)
        return

    async with SessionLocal() as db:
        order = await db.scalar(select(Order).where(Order.id == order_id))
        if not order or (order.creator_id != user_id and order.shipper_id != user_id):
            await websocket.close(code=4003)
            return
        if order.status not in _ACTIVE_STATUSES:
            await websocket.close(code=4004)
            return
        user_row = await db.scalar(select(User).where(User.id == user_id))
        sender_name = (user_row.display_name or user_row.username) if user_row else "Ẩn danh"

    await websocket.accept()
    channel = _chat_channel(order_id)

    r = await get_redis()
    pubsub = r.pubsub()
    await pubsub.subscribe(channel)

    async def _redis_to_ws() -> None:
        try:
            async for message in pubsub.listen():
                if message["type"] != "message":
                    continue
                try:
                    await websocket.send_text(message["data"])
                except Exception:
                    break
        except asyncio.CancelledError:
            pass

    listener = asyncio.create_task(_redis_to_ws())

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                content = json.loads(raw).get("content", "").strip()
            except (json.JSONDecodeError, AttributeError):
                continue
            if not content:
                continue

            async with SessionLocal() as db:
                msg = ChatMessage(order_id=order_id, sender_id=user_id, content=content)
                db.add(msg)
                await db.flush()
                payload = json.dumps({
                    "id": str(msg.id),
                    "sender_id": str(user_id),
                    "sender_name": sender_name,
                    "content": content,
                    "created_at": msg.created_at.isoformat(),
                })

                order_row = await db.scalar(select(Order).where(Order.id == order_id))
                recipient_id = (
                    order_row.creator_id
                    if order_row and order_row.shipper_id == user_id
                    else (order_row.shipper_id if order_row else None)
                )
                tokens: list[str] = []
                if recipient_id:
                    rows = await db.execute(
                        select(DeviceToken.token).where(DeviceToken.user_id == recipient_id)
                    )
                    tokens = list(rows.scalars().all())

                await db.commit()

            await r.publish(channel, payload)

            if tokens:
                preview = content if len(content) <= 60 else content[:57] + "..."
                stale = await send_push(
                    tokens=tokens,
                    title=f"Tin nhắn từ {sender_name}",
                    body=preview,
                    data={"order_id": str(order_id), "type": "chat"},
                )
                if stale:
                    async with SessionLocal() as db_prune:
                        await prune_stale_tokens(db_prune, stale)

    except WebSocketDisconnect:
        pass
    finally:
        listener.cancel()
        try:
            await pubsub.unsubscribe(channel)
            await pubsub.aclose()
        except Exception:
            pass
        logger.info("Chat WS disconnected order=%s user=%s", order_id, user_id)


# ─── WebSocket: user event stream (calls, cancel) ────────────

@router.websocket("/ws/user/events")
async def ws_user_events(
    websocket: WebSocket,
    token: str = Query(...),
):
    """Per-user event stream. Delivers call/cancel events instantly when the
    app is in the foreground, complementing FCM which can be slow."""
    try:
        user_id = uuid.UUID(decode_access_token(token))
    except (JWTError, ValueError):
        await websocket.close(code=4001)
        return

    await websocket.accept()
    channel = _user_channel(user_id)

    r = await get_redis()
    pubsub = r.pubsub()
    await pubsub.subscribe(channel)

    # Deliver any call that was initiated while this client was offline.
    # Subscribe first, then check — avoids a race where a new call arrives
    # between the Redis GET and the subscribe.
    # Delete immediately after sending (consume pattern) so the next reconnect
    # doesn't re-deliver the same call and spam the user.
    pending_raw = await r.get(_pending_call_key(user_id))
    if pending_raw:
        try:
            await websocket.send_text(pending_raw)
            await r.delete(_pending_call_key(user_id))
            logger.info("Delivered pending call to user %s on WS reconnect", user_id)
        except Exception:
            pass

    # Deliver all pending missed calls (max 3) accumulated while B was offline.
    # LRANGE returns newest-first (LPUSH order); deliver oldest-first by reversing.
    key = _pending_missed_call_key(user_id)
    missed_items = await r.lrange(key, 0, -1)
    if missed_items:
        await r.delete(key)
        for item in reversed(missed_items):
            try:
                await websocket.send_text(item)
            except Exception:
                break
        logger.info("Delivered %d pending missed call(s) to user %s", len(missed_items), user_id)

    async def _redis_to_ws() -> None:
        try:
            async for message in pubsub.listen():
                if message["type"] != "message":
                    continue
                try:
                    await websocket.send_text(message["data"])
                except Exception:
                    break
        except asyncio.CancelledError:
            pass

    listener = asyncio.create_task(_redis_to_ws())

    try:
        while True:
            # Keep connection alive; client may send "ping"
            raw = await websocket.receive_text()
            if raw == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        pass
    finally:
        listener.cancel()
        try:
            await pubsub.unsubscribe(channel)
            await pubsub.aclose()
        except Exception:
            pass
        logger.info("User event WS disconnected user=%s", user_id)
