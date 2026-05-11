import uuid
from datetime import datetime, timezone

from jose import JWTError
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    hash_password,
    hash_refresh_token,
    refresh_token_expire,
    verify_password,
)
from app.models.user import RefreshToken, User
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse


class AuthError(Exception):
    def __init__(self, detail: str, status_code: int = 401):
        self.detail = detail
        self.status_code = status_code


async def register(db: AsyncSession, data: RegisterRequest) -> User:
    # Check uniqueness
    existing = await db.scalar(select(User).where(User.username == data.username))
    if existing:
        raise AuthError("Username đã tồn tại", 409)

    # Restore order_slots from previous deleted account with same phone
    saved_slots: int | None = None
    if data.phone:
        row = await db.execute(
            text("SELECT order_slots FROM deleted_account_slots WHERE phone = :phone"),
            {"phone": data.phone},
        )
        saved_slots = row.scalar_one_or_none()

    user = User(
        username=data.username,
        password_hash=hash_password(data.password),
        display_name=data.display_name or data.username,
        phone=data.phone,
        email=data.email,
        apt_building=data.apt_building,
        apt_floor=data.apt_floor,
        apt_room=data.apt_room,
        order_slots=saved_slots if saved_slots is not None else 5,
    )
    db.add(user)
    await db.flush()

    if saved_slots is not None:
        await db.execute(
            text("DELETE FROM deleted_account_slots WHERE phone = :phone"),
            {"phone": data.phone},
        )

    await db.refresh(user)  # fetch server-generated fields (created_at, updated_at)
    return user


async def login(db: AsyncSession, data: LoginRequest) -> TokenResponse:
    user = await db.scalar(select(User).where(User.username == data.username))
    if not user or not verify_password(data.password, user.password_hash):
        raise AuthError("Sai username hoặc mật khẩu")
    if not user.is_active:
        raise AuthError("Tài khoản đã bị khoá", 403)

    # Update last_seen
    user.last_seen_at = datetime.now(timezone.utc)

    access_token = create_access_token(str(user.id))
    raw_refresh, refresh_hash = create_refresh_token()

    db.add(RefreshToken(
        user_id=user.id,
        token_hash=refresh_hash,
        expires_at=refresh_token_expire(),
    ))

    return TokenResponse(access_token=access_token, refresh_token=raw_refresh)


async def refresh_access_token(db: AsyncSession, raw_token: str) -> TokenResponse:
    token_hash = hash_refresh_token(raw_token)
    rt = await db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked == False,
            RefreshToken.expires_at > datetime.now(timezone.utc),
        )
    )
    if not rt:
        raise AuthError("Refresh token không hợp lệ hoặc đã hết hạn")

    # Rotate: revoke old, issue new
    rt.revoked = True
    raw_new, hash_new = create_refresh_token()
    db.add(RefreshToken(
        user_id=rt.user_id,
        token_hash=hash_new,
        expires_at=refresh_token_expire(),
    ))

    access_token = create_access_token(str(rt.user_id))
    return TokenResponse(access_token=access_token, refresh_token=raw_new)


async def get_current_user(db: AsyncSession, token: str) -> User:
    try:
        user_id = decode_access_token(token)
    except JWTError:
        raise AuthError("Token không hợp lệ")

    user = await db.get(User, uuid.UUID(user_id))
    if not user or not user.is_active:
        raise AuthError("Người dùng không tồn tại hoặc đã bị khoá", 403)
    return user
