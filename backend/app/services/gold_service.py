"""
All gold mutations go through here.
Every operation is wrapped in a DB transaction and writes to gold_ledger
before modifying users.gold_balance – ensuring a complete audit trail.
"""
import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gold import GoldLedger, GoldTxType
from app.models.user import User


class GoldError(Exception):
    def __init__(self, detail: str, status_code: int = 400):
        self.detail = detail
        self.status_code = status_code


async def _record_and_update(
    db: AsyncSession,
    user_id: uuid.UUID,
    amount: Decimal,          # positive = credit, negative = debit
    tx_type: GoldTxType,
    order_id: uuid.UUID | None = None,
    description: str | None = None,
    idempotency_key: str | None = None,
) -> float:
    """
    Atomically debit/credit a user's gold balance.
    Returns the new balance.
    Raises GoldError on insufficient funds or duplicate idempotency key.
    """
    # Fast-path idempotency check (no lock – avoids unnecessary row lock on cache hits).
    if idempotency_key:
        existing = await db.scalar(
            select(GoldLedger).where(GoldLedger.idempotency_key == idempotency_key)
        )
        if existing:
            return float(existing.balance_after)

    # Lock the user row so concurrent deductions are serialised.
    result = await db.execute(
        select(User)
        .where(User.id == user_id)
        .with_for_update()
    )
    user = result.scalar_one_or_none()
    if not user:
        raise GoldError("Người dùng không tồn tại", 404)

    # Re-check idempotency inside the lock: handles the case where two concurrent
    # requests with the same key both passed the fast-path check above (because
    # neither had committed yet).  After acquiring the lock the first request's
    # GoldLedger entry is now visible, so the second can return gracefully instead
    # of hitting a UNIQUE-constraint error.
    if idempotency_key:
        existing = await db.scalar(
            select(GoldLedger).where(GoldLedger.idempotency_key == idempotency_key)
        )
        if existing:
            return float(existing.balance_after)

    new_balance = Decimal(str(user.gold_balance)) + amount
    if new_balance < 0:
        raise GoldError(
            f"Số dư gold không đủ (hiện tại: {user.gold_balance}, cần: {abs(float(amount))})",
            402,
        )

    user.gold_balance = new_balance
    db.add(GoldLedger(
        user_id=user_id,
        order_id=order_id,
        tx_type=tx_type,
        amount=float(amount),
        balance_after=float(new_balance),
        description=description,
        idempotency_key=idempotency_key,
    ))
    return float(new_balance)


async def lock_gold_for_order(
    db: AsyncSession,
    user_id: uuid.UUID,
    order_id: uuid.UUID,
    amount: float,
    order_note: str | None = None,
) -> float:
    """Deduct gold from creator when they create an order."""
    return await _record_and_update(
        db, user_id, Decimal(str(-amount)),
        GoldTxType.order_lock, order_id=order_id,
        description=order_note,
        idempotency_key=f"lock:{order_id}",
    )


async def lock_gold_for_renew(
    db: AsyncSession,
    user_id: uuid.UUID,
    order_id: uuid.UUID,
    amount: float,
    previous_expires_at: datetime,
    order_note: str | None = None,
) -> float:
    """Re-lock gold when creator renews an expired order.

    Uses the old expires_at timestamp as the idempotency discriminator so that:
    - Retrying the same renewal attempt is safe (same key → no double deduction).
    - A second renewal after the order expires again gets a fresh key.
    """
    key_suffix = int(previous_expires_at.timestamp())
    return await _record_and_update(
        db, user_id, Decimal(str(-amount)),
        GoldTxType.order_lock, order_id=order_id,
        description=order_note,
        idempotency_key=f"renew_lock:{order_id}:{key_suffix}",
    )


async def reward_shipper(
    db: AsyncSession,
    shipper_id: uuid.UUID,
    order_id: uuid.UUID,
    amount: float,
    order_note: str | None = None,
) -> float:
    """Credit gold to shipper after accepting an order."""
    return await _record_and_update(
        db, shipper_id, Decimal(str(amount)),
        GoldTxType.order_reward, order_id=order_id,
        description=order_note,
        idempotency_key=f"reward:{order_id}",
    )


async def refund_creator(
    db: AsyncSession,
    creator_id: uuid.UUID,
    order_id: uuid.UUID,
    amount: float,
    order_note: str | None = None,
) -> float:
    """Refund gold to creator when order is expired or cancelled (before accept)."""
    return await _record_and_update(
        db, creator_id, Decimal(str(amount)),
        GoldTxType.order_refund, order_id=order_id,
        description=order_note,
        idempotency_key=f"refund:{order_id}",
    )


async def partial_refund_on_delivery(
    db: AsyncSession,
    creator_id: uuid.UUID,
    order_id: uuid.UUID,
    amount: float,
    order_note: str | None = None,
) -> float:
    """Refund the gold difference to creator when shipper voluntarily reduces the reward."""
    return await _record_and_update(
        db, creator_id, Decimal(str(amount)),
        GoldTxType.order_refund, order_id=order_id,
        description=order_note,
        idempotency_key=f"delivery_partial_refund:{order_id}",
    )


async def refund_creator_on_accepted_cancel(
    db: AsyncSession,
    creator_id: uuid.UUID,
    order_id: uuid.UUID,
    amount: float,
    order_note: str | None = None,
) -> float:
    """Refund gold to creator when creator cancels an accepted order within the grace period."""
    return await _record_and_update(
        db, creator_id, Decimal(str(amount)),
        GoldTxType.order_refund, order_id=order_id,
        description=order_note,
        idempotency_key=f"creator_cancel_accepted:{order_id}",
    )


async def refund_creator_on_shipper_cancel(
    db: AsyncSession,
    creator_id: uuid.UUID,
    order_id: uuid.UUID,
    amount: float,
    order_note: str | None = None,
) -> float:
    """Refund gold to creator when shipper cancels an accepted/delivering order."""
    return await _record_and_update(
        db, creator_id, Decimal(str(amount)),
        GoldTxType.order_refund, order_id=order_id,
        description=order_note,
        idempotency_key=f"shipper_cancel_refund:{order_id}",
    )


async def adjust_gold_for_order_edit(
    db: AsyncSession,
    creator_id: uuid.UUID,
    order_id: uuid.UUID,
    old_amount: float,
    new_amount: float,
    order_note: str | None = None,
) -> None:
    """Adjust locked gold when creator edits the reward on a pending order."""
    diff = new_amount - old_amount
    if diff == 0:
        return
    # Encode new_amount in cents to avoid float key collisions, e.g. "edit_lock:xxx:12000"
    new_cents = int(round(new_amount * 100))
    if diff > 0:
        await _record_and_update(
            db, creator_id, Decimal(str(-diff)),
            GoldTxType.order_lock, order_id=order_id,
            description=order_note,
            idempotency_key=f"edit_lock:{order_id}:{new_cents}",
        )
    else:
        await _record_and_update(
            db, creator_id, Decimal(str(-diff)),  # -diff > 0 → credit
            GoldTxType.order_refund, order_id=order_id,
            description=order_note,
            idempotency_key=f"edit_refund:{order_id}:{new_cents}",
        )


async def reduce_gold_in_delivery(
    db: AsyncSession,
    creator_id: uuid.UUID,
    order_id: uuid.UUID,
    diff: float,
    new_gold: float,
    order_note: str | None = None,
) -> float:
    """Refund the gold difference to creator when shipper reduces reward while in delivering state."""
    new_cents = int(round(new_gold * 100))
    return await _record_and_update(
        db, creator_id, Decimal(str(diff)),
        GoldTxType.order_refund, order_id=order_id,
        description=order_note,
        idempotency_key=f"reduce_delivering:{order_id}:{new_cents}",
    )


async def bonus_gold_on_completion(
    db: AsyncSession,
    creator_id: uuid.UUID,
    shipper_id: uuid.UUID,
    order_id: uuid.UUID,
    bonus: float,
    order_note: str | None = None,
) -> None:
    """Deduct bonus gold from creator and credit it to shipper at order completion."""
    # Lock in UUID order (same deadlock-prevention rule as dispute_gold).
    if creator_id <= shipper_id:
        await _record_and_update(
            db, creator_id, Decimal(str(-bonus)),
            GoldTxType.order_lock, order_id=order_id,
            description=order_note,
            idempotency_key=f"bonus_complete_deduct:{order_id}",
        )
        await _record_and_update(
            db, shipper_id, Decimal(str(bonus)),
            GoldTxType.order_reward, order_id=order_id,
            description=order_note,
            idempotency_key=f"bonus_complete_reward:{order_id}",
        )
    else:
        await _record_and_update(
            db, shipper_id, Decimal(str(bonus)),
            GoldTxType.order_reward, order_id=order_id,
            description=order_note,
            idempotency_key=f"bonus_complete_reward:{order_id}",
        )
        await _record_and_update(
            db, creator_id, Decimal(str(-bonus)),
            GoldTxType.order_lock, order_id=order_id,
            description=order_note,
            idempotency_key=f"bonus_complete_deduct:{order_id}",
        )


async def top_up(
    db: AsyncSession,
    user_id: uuid.UUID,
    amount: float,
    payment_tx_id: str,  # external payment transaction ID – required for idempotency
) -> float:
    return await _record_and_update(
        db, user_id, Decimal(str(amount)),
        GoldTxType.top_up,
        description="Nạp gold",
        idempotency_key=f"topup:{payment_tx_id}",
    )
