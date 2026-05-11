from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.limiter import limiter
from app.database import get_db
from app.schemas.auth import LoginRequest, RefreshRequest, RegisterRequest, TokenResponse
from app.schemas.user import UserProfile
from app.services.auth_service import AuthError, login, refresh_access_token, register

router = APIRouter(prefix="/auth", tags=["auth"])


def _raise(e: AuthError) -> None:
    raise HTTPException(status_code=e.status_code, detail=e.detail)


@router.post("/register", response_model=UserProfile, status_code=201)
@limiter.limit("5/minute")
async def register_endpoint(request: Request, data: RegisterRequest, db: AsyncSession = Depends(get_db)):
    try:
        user = await register(db, data)
        return user
    except AuthError as e:
        _raise(e)


@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
async def login_endpoint(request: Request, data: LoginRequest, db: AsyncSession = Depends(get_db)):
    try:
        return await login(db, data)
    except AuthError as e:
        _raise(e)


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("30/minute")
async def refresh_endpoint(request: Request, data: RefreshRequest, db: AsyncSession = Depends(get_db)):
    try:
        return await refresh_access_token(db, data.refresh_token)
    except AuthError as e:
        _raise(e)
