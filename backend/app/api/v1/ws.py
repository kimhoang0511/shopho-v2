"""
WebSocket endpoint – real-time order events for all connected clients.
Architecture:
  - Each connected Flutter client subscribes to this endpoint, optionally
    passing apartment_ids to receive only events for those apartments.
  - The backend publishes events to Redis pub/sub channel.
  - A single asyncio task per server instance listens to Redis and
    broadcasts to matching local WebSocket connections.
  - Works correctly in multi-worker setups because Redis acts as the
    message bus between workers.

Filtering:
  - Client passes ?apartment_ids=<uuid>&apartment_ids=<uuid> to subscribe
    to specific apartments. Events with a matching ship_apartment_id are
    delivered; events without apartment_id (e.g. accepted/completed) are
    always delivered so the client can remove orders from its list.
  - Clients that pass no apartment_ids receive all events (backward-compat).
"""
import asyncio
import json
import logging
import uuid

import redis.asyncio as aioredis
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from jose import JWTError

from app.config import get_settings
from app.core.redis import ORDER_CHANNEL, get_redis
from app.core.security import decode_access_token

logger = logging.getLogger(__name__)
router = APIRouter(tags=["websocket"])

# Maps each connected WebSocket to the set of apartment_id strings it subscribed to.
# An empty frozenset means "no filter" — receives all events.
_connections: dict[WebSocket, frozenset[str]] = {}
_listener_task: asyncio.Task | None = None


async def _redis_listener() -> None:
    """Long-running task: receive from Redis, fan-out to subscribed websockets."""
    settings = get_settings()
    r = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe(ORDER_CHANNEL)
    logger.info("WebSocket Redis listener started")
    try:
        async for message in pubsub.listen():
            if message["type"] != "message":
                continue

            # Extract apartment_id from the event payload for filtering.
            event_apt_id: str | None = None
            try:
                payload = json.loads(message["data"])
                event_apt_id = payload.get("data", {}).get("ship_apartment_id")
            except Exception:
                pass

            dead: set[WebSocket] = set()
            for ws, subs in list(_connections.items()):
                # subs is empty → no filter → always deliver
                # subs is non-empty → only deliver when apartment matches
                if subs and event_apt_id and event_apt_id not in subs:
                    continue
                try:
                    await ws.send_text(message["data"])
                except Exception:
                    dead.add(ws)

            for ws in dead:
                _connections.pop(ws, None)

    except asyncio.CancelledError:
        pass
    finally:
        await pubsub.unsubscribe(ORDER_CHANNEL)
        await r.aclose()
        logger.info("WebSocket Redis listener stopped")


def ensure_listener_running() -> None:
    global _listener_task
    if _listener_task is None or _listener_task.done():
        _listener_task = asyncio.create_task(_redis_listener())


@router.websocket("/ws/orders")
async def ws_orders(
    websocket: WebSocket,
    apartment_ids: list[uuid.UUID] = Query(default=[]),
):
    # Authenticate via query-param token (Flutter can't set headers on WS)
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4001)
        return
    try:
        decode_access_token(token)
    except JWTError:
        await websocket.close(code=4001)
        return

    await websocket.accept()
    ensure_listener_running()

    subs = frozenset(str(aid) for aid in apartment_ids)
    _connections[websocket] = subs
    logger.info("WS client connected (filter=%d apts). Total: %d", len(subs), len(_connections))

    try:
        # Keep connection alive; client sends pings
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        pass
    finally:
        _connections.pop(websocket, None)
        logger.info("WS client disconnected. Total: %d", len(_connections))
