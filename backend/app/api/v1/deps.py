"""Shared FastAPI dependencies."""
import uuid

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import decode_access_token
from app.database import get_db
from app.models.user import User
from app.services.auth_service import AuthError, get_current_user

bearer = HTTPBearer()


async def current_user(
    creds: HTTPAuthorizationCredentials = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    try:
        return await get_current_user(db, creds.credentials)
    except AuthError as e:
        raise HTTPException(status_code=e.status_code, detail=e.detail)


async def verify_token(
    creds: HTTPAuthorizationCredentials = Depends(bearer),
) -> None:
    """Validates JWT only — no DB query. Use for read-only endpoints that just need auth."""
    try:
        decode_access_token(creds.credentials)
    except JWTError:
        raise HTTPException(status_code=401, detail="Token không hợp lệ")


async def current_user_id(
    creds: HTTPAuthorizationCredentials = Depends(bearer),
) -> uuid.UUID:
    """Returns user_id from JWT without a DB query. Use for endpoints that only need user identity."""
    try:
        return uuid.UUID(decode_access_token(creds.credentials))
    except (JWTError, ValueError):
        raise HTTPException(status_code=401, detail="Token không hợp lệ")
