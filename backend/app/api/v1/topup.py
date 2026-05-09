"""
Gold top-up via VietQR bank transfer.

Flow:
  1. POST /users/me/gold/topup/create  → tạo pending order, trả về order_code + QR info
  2. User quét QR, chuyển khoản với nội dung = order_code
  3. POST /webhook/payment             → SePay/Casso gọi khi nhận được tiền
  4. GET  /users/me/gold/topup/{code}  → frontend poll để xác nhận
"""
import random
import string
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import current_user
from app.config import get_settings
from app.database import get_db
from app.models.gold import GoldTopUpOrder
from app.models.user import User
from app.services.gold_service import top_up

router = APIRouter(tags=["topup"])

settings = get_settings()

# 1000 VND = 1 gold
VND_PER_GOLD = 1000

# Preset gold packages (gold → vnd)
GOLD_PACKAGES = [10, 20, 50, 100, 200, 500]


# ── Helpers ───────────────────────────────────────────────────

def _gen_order_code() -> str:
    chars = string.ascii_uppercase + string.digits
    return "SH" + "".join(random.choices(chars, k=6))


# ── Schemas ───────────────────────────────────────────────────

class TopUpCreateBody(BaseModel):
    gold_amount: int = Field(..., ge=10, le=10000)


class TopUpCreateResponse(BaseModel):
    order_code: str
    gold_amount: int
    amount_vnd: int
    qr_url: str
    bank_id: str
    account_number: str


class TopUpStatusResponse(BaseModel):
    status: str          # pending | completed | expired
    gold_amount: int
    amount_vnd: int


# ── Endpoints ─────────────────────────────────────────────────

@router.post("/users/me/gold/topup/create", response_model=TopUpCreateResponse)
async def create_topup(
    body: TopUpCreateBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    if body.gold_amount not in GOLD_PACKAGES:
        raise HTTPException(400, f"Gói tiền hợp lệ: {GOLD_PACKAGES}")

    amount_vnd = body.gold_amount * VND_PER_GOLD

    # Generate unique order code (retry on collision, extremely rare)
    for _ in range(5):
        code = _gen_order_code()
        exists = await db.scalar(
            select(GoldTopUpOrder).where(GoldTopUpOrder.order_code == code)
        )
        if not exists:
            break
    else:
        raise HTTPException(500, "Không thể tạo mã đơn, thử lại")

    order = GoldTopUpOrder(
        user_id=user.id,
        order_code=code,
        gold_amount=body.gold_amount,
        amount_vnd=amount_vnd,
        status="pending",
    )
    db.add(order)

    qr_url = (
        f"https://img.vietqr.io/image/"
        f"{settings.vietqr_bank_id}-{settings.vietqr_account_number}-compact2.jpg"
        f"?amount={amount_vnd}&addInfo={code}"
    )

    return TopUpCreateResponse(
        order_code=code,
        gold_amount=body.gold_amount,
        amount_vnd=amount_vnd,
        qr_url=qr_url,
        bank_id=settings.vietqr_bank_id,
        account_number=settings.vietqr_account_number,
    )


@router.get("/users/me/gold/topup/{order_code}", response_model=TopUpStatusResponse)
async def get_topup_status(
    order_code: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_user),
):
    order = await db.scalar(
        select(GoldTopUpOrder).where(
            GoldTopUpOrder.order_code == order_code,
            GoldTopUpOrder.user_id == user.id,
        )
    )
    if not order:
        raise HTTPException(404, "Không tìm thấy đơn nạp tiền")

    return TopUpStatusResponse(
        status=order.status,
        gold_amount=int(order.gold_amount),
        amount_vnd=order.amount_vnd,
    )


@router.post("/webhook/payment", status_code=200)
async def payment_webhook(
    request: Request,
    db: AsyncSession = Depends(get_db),
    authorization: str = Header(default=""),
):
    """
    Webhook từ Casso khi nhận được giao dịch chuyển khoản.

    Casso gửi header: Authorization: Apikey <PAYMENT_WEBHOOK_SECRET>
    Payload JSON chứa:
      - data[].amount  : số tiền (int, VND)
      - data[].description : nội dung chuyển khoản (chứa order_code)
      - data[].is_incoming : True nếu là tiền vào
    """
    # Verify Casso secret — Casso gửi raw key hoặc "Apikey <key>"
    if settings.payment_webhook_secret:
        secret = settings.payment_webhook_secret
        if authorization not in (secret, f"Apikey {secret}"):
            raise HTTPException(401, "Invalid webhook secret")

    import re

    payload = await request.json()

    # Casso gửi: {"error": 0, "data": [{...}, {...}]}
    transactions = payload.get("data", [])
    if not isinstance(transactions, list):
        transactions = [payload]  # fallback: single-transaction format

    results = []
    for tx in transactions:
        # Chỉ xử lý tiền vào
        if not tx.get("is_incoming", True):
            continue

        transfer_amount: int = int(tx.get("amount", 0))
        content: str = tx.get("description", "") or ""
        tx_id: str = str(tx.get("tid", tx.get("id", "")))

        if transfer_amount <= 0:
            continue

        # Tìm order_code dạng SHxxxxxx (gold) hoặc SLxxxxxx (slots) trong nội dung CK
        match = re.search(r'\bS[HL][A-Z0-9]{6}\b', content.upper())
        if not match:
            results.append({"tid": tx_id, "status": "no_order_code"})
            continue

        order_code = match.group(0)

        if order_code.startswith("SL"):
            # ── Slot top-up ───────────────────────────────────
            from app.models.gold import SlotTopUpOrder
            from sqlalchemy import update as sa_update

            slot_order = await db.scalar(
                select(SlotTopUpOrder).where(
                    SlotTopUpOrder.order_code == order_code,
                    SlotTopUpOrder.status == "pending",
                )
            )
            if not slot_order:
                results.append({"tid": tx_id, "status": "order_not_found_or_already_processed"})
                continue

            if transfer_amount < slot_order.amount_vnd:
                results.append({"tid": tx_id, "status": "amount_mismatch"})
                continue

            from app.models.user import User as UserModel
            await db.execute(
                sa_update(UserModel)
                .where(UserModel.id == slot_order.user_id)
                .values(order_slots=UserModel.order_slots + slot_order.slots_amount)
            )
            slot_order.status = "completed"
            slot_order.completed_at = datetime.now(timezone.utc)
            results.append({"tid": tx_id, "status": "ok", "order_code": order_code, "slots_credited": slot_order.slots_amount})

        else:
            # ── Gold top-up (SH prefix) ───────────────────────
            order = await db.scalar(
                select(GoldTopUpOrder).where(
                    GoldTopUpOrder.order_code == order_code,
                    GoldTopUpOrder.status == "pending",
                )
            )
            if not order:
                results.append({"tid": tx_id, "status": "order_not_found_or_already_processed"})
                continue

            if transfer_amount < order.amount_vnd:
                results.append({"tid": tx_id, "status": "amount_mismatch"})
                continue

            await top_up(db, order.user_id, float(order.gold_amount), tx_id or order_code)
            order.status = "completed"
            order.completed_at = datetime.now(timezone.utc)
            results.append({"tid": tx_id, "status": "ok", "order_code": order_code, "gold_credited": float(order.gold_amount)})

    return {"error": 0, "results": results}
