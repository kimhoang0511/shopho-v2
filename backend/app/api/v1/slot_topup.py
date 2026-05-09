"""
Slot top-up via VietQR bank transfer.

Flow:
  1. POST /api/v1/users/me/slots/topup/create  → tạo pending order, trả về order_code + QR info
  2. User quét QR, chuyển khoản với nội dung = order_code
  3. POST /webhook/payment                      → webhook xử lý cả SH (gold) và SL (slots)
  4. GET  /api/v1/users/me/slots/topup/{code}   → frontend poll để xác nhận
"""
import random
import string
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import current_user
from app.config import get_settings
from app.database import get_db
from app.models.gold import SlotTopUpOrder
from app.models.user import User

router = APIRouter(tags=["slot-topup"])


class SlotPackageItem(BaseModel):
    slots: int
    price_vnd: int


def _gen_slot_order_code() -> str:
    chars = string.ascii_uppercase + string.digits
    return "SL" + "".join(random.choices(chars, k=6))


@router.get("/slots/topup/packages", response_model=list[SlotPackageItem])
async def list_slot_packages():
    return [
        SlotPackageItem(slots=slots, price_vnd=price)
        for slots, price in get_settings().slot_packages.items()
    ]


class SlotTopUpCreateBody(BaseModel):
    slots_amount: int


class SlotTopUpCreateResponse(BaseModel):
    order_code: str
    slots_amount: int
    amount_vnd: int
    qr_url: str
    bank_id: str
    account_number: str


class SlotTopUpStatusResponse(BaseModel):
    status: str          # pending | completed
    slots_amount: int
    amount_vnd: int


@router.post("/users/me/slots/topup/create", response_model=SlotTopUpCreateResponse)
async def create_slot_topup(
    body: SlotTopUpCreateBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    packages = get_settings().slot_packages
    if body.slots_amount not in packages:
        raise HTTPException(400, f"Gói lượt hợp lệ: {list(packages.keys())}")

    amount_vnd = packages[body.slots_amount]

    for _ in range(5):
        code = _gen_slot_order_code()
        exists = await db.scalar(
            select(SlotTopUpOrder).where(SlotTopUpOrder.order_code == code)
        )
        if not exists:
            break
    else:
        raise HTTPException(500, "Không thể tạo mã đơn, thử lại")

    order = SlotTopUpOrder(
        user_id=user.id,
        order_code=code,
        slots_amount=body.slots_amount,
        amount_vnd=amount_vnd,
        status="pending",
    )
    db.add(order)

    cfg = get_settings()
    qr_url = (
        f"https://img.vietqr.io/image/"
        f"{cfg.vietqr_bank_id}-{cfg.vietqr_account_number}-compact2.jpg"
        f"?amount={amount_vnd}&addInfo={code}"
    )

    return SlotTopUpCreateResponse(
        order_code=code,
        slots_amount=body.slots_amount,
        amount_vnd=amount_vnd,
        qr_url=qr_url,
        bank_id=cfg.vietqr_bank_id,
        account_number=cfg.vietqr_account_number,
    )


@router.get("/users/me/slots/topup/{order_code}", response_model=SlotTopUpStatusResponse)
async def get_slot_topup_status(
    order_code: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    order = await db.scalar(
        select(SlotTopUpOrder).where(
            SlotTopUpOrder.order_code == order_code,
            SlotTopUpOrder.user_id == user.id,
        )
    )
    if not order:
        raise HTTPException(404, "Không tìm thấy đơn nạp lượt")

    return SlotTopUpStatusResponse(
        status=order.status,
        slots_amount=order.slots_amount,
        amount_vnd=order.amount_vnd,
    )
