import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import get_settings
from app.core.security import create_access_token, decode_access_token
from app.database import get_db
from app.models.apartment import Apartment, ApartmentBuilding
from app.schemas.apartment import ApartmentCreate, ApartmentOut, ApartmentUpdate
from app.services.storage_service import upload_image

router = APIRouter(prefix="/admin", tags=["admin"])
_bearer = HTTPBearer()
_ADMIN_SUBJECT = "admin"


def _admin_token() -> str:
    return create_access_token(_ADMIN_SUBJECT)


async def _require_admin(creds: HTTPAuthorizationCredentials = Depends(_bearer)) -> None:
    try:
        subject = decode_access_token(creds.credentials)
    except Exception:
        raise HTTPException(status_code=401, detail="Token không hợp lệ")
    if subject != _ADMIN_SUBJECT:
        raise HTTPException(status_code=403, detail="Không có quyền admin")


# ─── AUTH ───────────────────────────────────────────────────

@router.post("/login")
async def admin_login(body: dict):
    settings = get_settings()
    if body.get("username") != settings.admin_username or body.get("password") != settings.admin_password:
        raise HTTPException(status_code=401, detail="Sai thông tin đăng nhập admin")
    return {"access_token": _admin_token(), "token_type": "bearer"}


# ─── APARTMENTS LIST ────────────────────────────────────────

@router.get("/apartments", response_model=list[ApartmentOut])
async def list_apartments(db: AsyncSession = Depends(get_db), _=Depends(_require_admin)):
    result = await db.execute(
        select(Apartment).options(selectinload(Apartment.buildings)).order_by(Apartment.name)
    )
    return list(result.scalars().all())


# ─── IMAGE UPLOAD ───────────────────────────────────────────

@router.post("/apartments/{apt_id}/image", response_model=ApartmentOut)
async def upload_apartment_image(
    apt_id: uuid.UUID,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    _=Depends(_require_admin),
):
    apt = await db.scalar(select(Apartment).options(selectinload(Apartment.buildings)).where(Apartment.id == apt_id))
    if not apt:
        raise HTTPException(status_code=404, detail="Căn hộ không tồn tại")
    try:
        _, url = await upload_image(file, prefix="apartments")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as exc:
        import logging
        logging.getLogger(__name__).exception("Upload ảnh thất bại")
        raise HTTPException(status_code=500, detail=f"Upload ảnh thất bại: {exc}")
    apt.image_url = url
    await db.flush()
    await db.refresh(apt, ["buildings"])
    return apt


# ─── CREATE ─────────────────────────────────────────────────

@router.post("/apartments", response_model=ApartmentOut, status_code=201)
async def create_apartment(data: ApartmentCreate, db: AsyncSession = Depends(get_db), _=Depends(_require_admin)):
    apt = Apartment(name=data.name, address=data.address, image_url=data.image_url)
    db.add(apt)
    await db.flush()
    for bname in set(data.buildings):
        db.add(ApartmentBuilding(apartment_id=apt.id, name=bname.strip()))
    await db.flush()
    await db.refresh(apt, ["buildings"])
    return apt


# ─── UPDATE ─────────────────────────────────────────────────

@router.put("/apartments/{apt_id}", response_model=ApartmentOut)
async def update_apartment(apt_id: uuid.UUID, data: ApartmentUpdate, db: AsyncSession = Depends(get_db), _=Depends(_require_admin)):
    apt = await db.scalar(select(Apartment).options(selectinload(Apartment.buildings)).where(Apartment.id == apt_id))
    if not apt:
        raise HTTPException(status_code=404, detail="Căn hộ không tồn tại")
    if data.name is not None:
        apt.name = data.name
    if data.address is not None:
        apt.address = data.address
    if data.image_url is not None:
        apt.image_url = data.image_url
    if data.buildings is not None:
        for b in list(apt.buildings):
            await db.delete(b)
        await db.flush()
        for bname in set(data.buildings):
            db.add(ApartmentBuilding(apartment_id=apt.id, name=bname.strip()))
    await db.flush()
    await db.refresh(apt, ["buildings"])
    return apt


# ─── DELETE ─────────────────────────────────────────────────

@router.delete("/apartments/{apt_id}", status_code=204)
async def delete_apartment(apt_id: uuid.UUID, db: AsyncSession = Depends(get_db), _=Depends(_require_admin)):
    apt = await db.get(Apartment, apt_id)
    if not apt:
        raise HTTPException(status_code=404, detail="Căn hộ không tồn tại")
    await db.delete(apt)


# ─── FCM TEST ───────────────────────────────────────────────

@router.get("/device-tokens/{user_id}")
async def list_device_tokens(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(_require_admin),
):
    from app.models.user import DeviceToken
    result = await db.execute(select(DeviceToken).where(DeviceToken.user_id == user_id))
    tokens = result.scalars().all()
    return [{"id": str(t.id), "token": t.token, "platform": t.platform, "created_at": t.created_at} for t in tokens]


@router.post("/test-push")
async def test_push(
    body: dict,
    db: AsyncSession = Depends(get_db),
    _=Depends(_require_admin),
):
    from app.models.user import DeviceToken
    from app.core.fcm import send_push, prune_stale_tokens

    user_id = body.get("user_id")
    token = body.get("token")
    title = body.get("title", "Test thông báo")
    message = body.get("body", "Thông báo đẩy hoạt động!")

    if token:
        tokens = [token]
    elif user_id:
        result = await db.execute(
            select(DeviceToken).where(DeviceToken.user_id == uuid.UUID(user_id))
        )
        tokens = [t.token for t in result.scalars().all()]
    else:
        raise HTTPException(status_code=400, detail="Cần truyền 'user_id' hoặc 'token'")

    if not tokens:
        raise HTTPException(status_code=404, detail="Không tìm thấy device token nào")

    import base64, os as _os
    b64_raw = _os.environ.get("FIREBASE_SERVICE_ACCOUNT_B64", "")
    b64_info = {
        "present": bool(b64_raw),
        "length": len(b64_raw),
        "starts_with": b64_raw[:6] if b64_raw else "",
        "ends_with": b64_raw[-6:] if b64_raw else "",
        "has_leading_quote": b64_raw.startswith('"') if b64_raw else False,
        "has_newline": "\n" in b64_raw if b64_raw else False,
    }
    try:
        decoded = base64.b64decode(b64_raw.strip()).decode()
        import json as _json
        parsed = _json.loads(decoded)
        b64_info["decode_ok"] = True
        b64_info["project_id"] = parsed.get("project_id", "?")
    except Exception as decode_err:
        b64_info["decode_ok"] = False
        b64_info["decode_error"] = str(decode_err)

    fcm_init_error = None
    try:
        import firebase_admin
        from firebase_admin import credentials as _creds
        _sa_dict = _json.loads(base64.b64decode(b64_raw.strip()).decode())
        _cred = _creds.Certificate(_sa_dict)
        if not firebase_admin._apps:
            firebase_admin.initialize_app(_cred)
        from app.core import fcm as _fcm_mod
        _fcm_mod._initialized = True
    except Exception as _e:
        fcm_init_error = str(_e)

    from app.core.fcm import _init
    fcm_ready = _init()
    if not fcm_ready:
        raise HTTPException(status_code=500, detail={"message": "FCM chưa khởi tạo được", "b64_diagnostics": b64_info, "init_error": fcm_init_error})

    stale = await send_push(tokens, title, message, {"test": "true"})
    await prune_stale_tokens(db, stale)
    return {
        "fcm_initialized": fcm_ready,
        "tokens_found": len(tokens),
        "tokens_sent": len(tokens) - len(stale),
        "tokens_stale_deleted": len(stale),
        "status": "sent",
    }
