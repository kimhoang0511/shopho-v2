import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Numeric, String, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class GoldTxType(str, enum.Enum):
    top_up = "top_up"
    order_lock = "order_lock"
    order_reward = "order_reward"
    order_refund = "order_refund"
    withdrawal = "withdrawal"


class GoldLedger(Base):
    __tablename__ = "gold_ledger"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    order_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("orders.id"))
    tx_type: Mapped[GoldTxType] = mapped_column(Enum(GoldTxType, name="gold_tx_type"), nullable=False)
    amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    balance_after: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    idempotency_key: Mapped[str | None] = mapped_column(String(128), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))

    user: Mapped["User"] = relationship("User", back_populates="gold_transactions")


class SlotTopUpOrder(Base):
    """Tracks purchase of order-slot packages via bank transfer."""

    __tablename__ = "slot_topup_orders"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    order_code: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    slots_amount: Mapped[int] = mapped_column(nullable=False)
    amount_vnd: Mapped[int] = mapped_column(nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class GoldTopUpOrder(Base):
    __tablename__ = "gold_topup_orders"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    order_code: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    gold_amount: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    amount_vnd: Mapped[int] = mapped_column(nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
