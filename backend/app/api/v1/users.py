import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel
from sqlalchemy import delete, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.v1.deps import current_user, current_user_id, verify_token
from app.core.limiter import limiter, user_key
from app.database import get_db
from app.models.apartment import Apartment
from app.models.user import ShipperAlert, ShipperAlertLocation, User
from app.schemas.apartment import ApartmentOut
from app.schemas.user import UserProfile, UserUpdate

router = APIRouter(prefix="/users", tags=["users"])


@router.post("/me/ephemeral-token")
@limiter.limit("30/minute", key_func=user_key)
async def create_ephemeral_token(
    request: Request,
    user_id: uuid.UUID = Depends(current_user_id),
):
    """Issues a short-lived JWT (5 min) for WebSocket connections and external web integrations.
    If this token is captured in server logs, the exposure window is at most 5 minutes."""
    from app.core.security import create_access_token
    return {"token": create_access_token(str(user_id), expires_minutes=5)}


@router.get("/me", response_model=UserProfile)
async def get_me(user: User = Depends(current_user)):
    return user


@router.patch("/me", response_model=UserProfile)
async def update_me(
    data: UserUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    for field, value in data.model_dump(exclude_none=True).items():
        setattr(user, field, value)
    db.add(user)
    return user


@router.delete("/me", status_code=204)
async def delete_me(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    await db.delete(user)
    await db.commit()


@router.get("/apartments", response_model=list[ApartmentOut])
async def list_apartments_for_user(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(verify_token),
):
    result = await db.execute(
        select(Apartment).options(selectinload(Apartment.buildings)).order_by(Apartment.name)
    )
    return list(result.scalars().all())


@router.post("/me/device-token", status_code=204)
async def register_device_token(
    body: dict,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(current_user_id),
):
    from app.models.user import DeviceToken
    from sqlalchemy.dialects.postgresql import insert as pg_insert
    token = body.get("token", "").strip()
    platform = body.get("platform", "android").strip()
    if not token:
        return
    stmt = (
        pg_insert(DeviceToken)
        .values(user_id=user_id, token=token, platform=platform)
        .on_conflict_do_nothing()
    )
    await db.execute(stmt)
    await db.commit()


@router.delete("/me/device-token", status_code=204)
async def unregister_device_token(
    body: dict,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(current_user_id),
):
    from app.models.user import DeviceToken
    from sqlalchemy import delete
    token = body.get("token", "").strip()
    if not token:
        return
    await db.execute(
        delete(DeviceToken).where(DeviceToken.user_id == user_id, DeviceToken.token == token)
    )
    await db.commit()


# ─── Browse-alert (notification when new order matches filter) ─

class _AlertLocation(BaseModel):
    apartment_id: uuid.UUID
    building: str | None = None
    floor: int | None = None


class _BrowseAlertBody(BaseModel):
    enabled: bool
    min_gold: float | None = None
    locations: list[_AlertLocation] = []


@router.get("/me/browse-alert")
async def get_browse_alert(
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(current_user_id),
):
    alert = await db.scalar(
        select(ShipperAlert).where(ShipperAlert.user_id == user_id)
    )
    if alert is None:
        return {"enabled": False, "min_gold": None, "locations": []}
    return {
        "enabled": alert.enabled,
        "min_gold": float(alert.min_gold) if alert.min_gold is not None else None,
        "locations": [
            {
                "apartment_id": str(loc.apartment_id),
                "building": loc.building,
                "floor": loc.floor,
            }
            for loc in (alert.locations or [])
        ],
    }


@router.put("/me/browse-alert", status_code=204)
async def update_browse_alert(
    body: _BrowseAlertBody,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(current_user_id),
):
    from sqlalchemy.dialects.postgresql import insert as pg_insert

    # Upsert ShipperAlert (global settings)
    await db.execute(
        pg_insert(ShipperAlert)
        .values(user_id=user_id, enabled=body.enabled, min_gold=body.min_gold)
        .on_conflict_do_update(
            index_elements=["user_id"],
            set_={
                "enabled": body.enabled,
                "min_gold": body.min_gold,
                "updated_at": text("NOW()"),
            },
        )
    )

    # Replace all location rows for this user
    await db.execute(
        delete(ShipperAlertLocation).where(ShipperAlertLocation.user_id == user_id)
    )
    if body.locations:
        await db.execute(
            pg_insert(ShipperAlertLocation).values([
                {
                    "id": uuid.uuid4(),
                    "user_id": user_id,
                    "apartment_id": loc.apartment_id,
                    "building": loc.building,
                    "floor": loc.floor,
                }
                for loc in body.locations
            ]).on_conflict_do_nothing()
        )
