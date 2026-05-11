"""
Shared rate-limiter using slowapi + Redis storage.
Redis keeps counters consistent across multiple Uvicorn workers.

Two key functions:
  - get_remote_address : IP-based — used for unauthenticated endpoints (login, register)
  - user_key           : user ID from JWT — used for authenticated endpoints
"""
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.config import get_settings
from app.core.security import decode_access_token

settings = get_settings()


def user_key(request) -> str:
    """Rate-limit by user ID extracted from JWT; falls back to IP if token is absent/invalid."""
    try:
        auth = request.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            return decode_access_token(auth[7:])
    except Exception:
        pass
    return get_remote_address(request)


limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=settings.redis_url,
    strategy="fixed-window",
)
