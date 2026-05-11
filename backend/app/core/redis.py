"""
Redis client + helpers for:
  - Caching pending order lists (version-based invalidation)
  - Pub/Sub for real-time WebSocket broadcast
"""
import json
from typing import Any

import redis.asyncio as aioredis

from app.config import get_settings

settings = get_settings()

# Shared connection pool – created once at startup
_pool: aioredis.Redis | None = None

PENDING_ORDERS_KEY = "shopho:orders:pending"   # sorted set (score = expires_at unix)
ORDER_CHANNEL = "shopho:orders:events"          # pub/sub channel name
ORDERS_CACHE_TTL = 30                           # seconds per cached browse page
ORDERS_VERSION_KEY = "shopho:orders:v"          # monotonic counter; bump = invalidate all browse caches


async def get_redis() -> aioredis.Redis:
    global _pool
    if _pool is None:
        _pool = aioredis.from_url(settings.redis_url, decode_responses=True)
    return _pool


async def publish_event(event_type: str, payload: dict[str, Any]) -> None:
    """Broadcast an event to all WebSocket subscribers."""
    r = await get_redis()
    msg = json.dumps({"type": event_type, "data": payload})
    await r.publish(ORDER_CHANNEL, msg)


async def cache_set(key: str, value: Any, ttl: int = 30) -> None:
    r = await get_redis()
    await r.set(key, json.dumps(value), ex=ttl)


async def cache_get(key: str) -> Any | None:
    r = await get_redis()
    raw = await r.get(key)
    return json.loads(raw) if raw else None


async def cache_delete(key: str) -> None:
    r = await get_redis()
    await r.delete(key)


async def get_orders_version() -> int:
    """Return the current browse-cache generation counter."""
    r = await get_redis()
    v = await r.get(ORDERS_VERSION_KEY)
    return int(v) if v else 0


async def bump_orders_version() -> None:
    """Invalidate all browse caches by incrementing the generation counter."""
    r = await get_redis()
    await r.incr(ORDERS_VERSION_KEY)


async def close_redis() -> None:
    global _pool
    if _pool:
        await _pool.aclose()
        _pool = None
