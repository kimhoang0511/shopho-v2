import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Index, Numeric, SmallInteger, String, Text, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class OrderStatus(str, enum.Enum):
    pending = "pending"
    accepted = "accepted"
    completed = "completed"
    cancelled = "cancelled"
    expired = "expired"


class ShipLocationType(str, enum.Enum):
    building = "building"
    floor = "floor"
    room = "room"


VALIDITY_OPTIONS = {
    "7_min":    7,
    "15_min":   15,
    "30_min":   30,
    "1_hour":   60,
    "3_hours":  180,
    "6_hours":  360,
    "12_hours": 720,
}


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    creator_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    shipper_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))

    note: Mapped[str] = mapped_column(Text, nullable=False)
    gold_reward: Mapped[float] = mapped_column(Numeric(8, 2), nullable=False)

    ship_apartment_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("apartments.id", ondelete="SET NULL"), nullable=True)
    ship_apartment: Mapped["Apartment | None"] = relationship("Apartment", foreign_keys=[ship_apartment_id], lazy="selectin")
    ship_location: Mapped[ShipLocationType] = mapped_column(Enum(ShipLocationType, name="ship_location_type"), nullable=False)
    ship_building: Mapped[str | None] = mapped_column(String(20))
    ship_floor: Mapped[int | None] = mapped_column(SmallInteger)
    ship_room: Mapped[str | None] = mapped_column(String(20))

    validity_option: Mapped[str] = mapped_column(String(20), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[OrderStatus] = mapped_column(Enum(OrderStatus, name="order_status"), nullable=False, default=OrderStatus.pending)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"), onupdate=datetime.utcnow)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delivering_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    estimated_minutes: Mapped[int | None] = mapped_column(SmallInteger)
    estimated_delivery_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    total_gold: Mapped[float | None] = mapped_column(Numeric(8, 2))

    # relationships
    creator: Mapped["User"] = relationship("User", foreign_keys=[creator_id], back_populates="created_orders", lazy="selectin")
    shipper: Mapped["User | None"] = relationship("User", foreign_keys=[shipper_id], back_populates="shipped_orders", lazy="selectin")
    images: Mapped[list["OrderImage"]] = relationship("OrderImage", back_populates="order", lazy="selectin", order_by="OrderImage.sort_order")

    __table_args__ = (
        Index("idx_orders_pending_building", "ship_building", "created_at",
              postgresql_where=text("status = 'pending'")),
        Index("idx_orders_expires", "expires_at",
              postgresql_where=text("status = 'pending'")),
        Index("idx_orders_creator", "creator_id", "created_at"),
        Index("idx_orders_shipper", "shipper_id",
              postgresql_where=text("shipper_id IS NOT NULL")),
    )


class OrderImage(Base):
    __tablename__ = "order_images"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    order_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("orders.id"), nullable=False)
    storage_key: Mapped[str] = mapped_column(Text, nullable=False)
    public_url: Mapped[str] = mapped_column(Text, nullable=False)
    sort_order: Mapped[int] = mapped_column(SmallInteger, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))

    order: Mapped["Order"] = relationship("Order", back_populates="images")


class OrderHistory(Base):
    """Archived copy of closed orders (expired/completed/cancelled > 48h)."""

    __tablename__ = "order_history"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    creator_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    shipper_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))

    note: Mapped[str] = mapped_column(Text, nullable=False)
    gold_reward: Mapped[float] = mapped_column(Numeric(8, 2), nullable=False)

    ship_apartment_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    ship_location: Mapped[ShipLocationType] = mapped_column(Enum(ShipLocationType, name="ship_location_type"), nullable=False)
    ship_building: Mapped[str | None] = mapped_column(String(20))
    ship_floor: Mapped[int | None] = mapped_column(SmallInteger)
    ship_room: Mapped[str | None] = mapped_column(String(20))

    validity_option: Mapped[str] = mapped_column(String(20), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[OrderStatus] = mapped_column(Enum(OrderStatus, name="order_status"), nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delivering_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    estimated_minutes: Mapped[int | None] = mapped_column(SmallInteger)
    estimated_delivery_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Denormalised images from order_images (captured before cascade-delete)
    images: Mapped[list] = mapped_column(JSONB, nullable=False, server_default=text("'[]'::jsonb"))

    archived_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))

    __table_args__ = (
        Index("idx_order_history_creator", "creator_id", "archived_at"),
        Index("idx_order_history_shipper", "shipper_id", "archived_at",
              postgresql_where=text("shipper_id IS NOT NULL")),
        Index("idx_order_history_status", "status", "archived_at"),
    )


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    order_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("orders.id"))
    type: Mapped[str] = mapped_column(String(50), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))

    __table_args__ = (
        Index("idx_notifications_unread", "user_id", "is_read", "created_at",
              postgresql_where=text("is_read = FALSE")),
    )
