import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Numeric, SmallInteger, String, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    email: Mapped[str | None] = mapped_column(String(255), unique=True)
    phone: Mapped[str | None] = mapped_column(String(20), unique=True)
    password_hash: Mapped[str] = mapped_column(String, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(100))
    avatar_url: Mapped[str | None] = mapped_column(String)
    gold_balance: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=100.0)
    apartment_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("apartments.id", ondelete="SET NULL"))
    apt_building: Mapped[str | None] = mapped_column(String(20))
    apt_floor: Mapped[int | None] = mapped_column(SmallInteger)
    apt_room: Mapped[str | None] = mapped_column(String(20))
    bank_code: Mapped[str | None] = mapped_column(String(50))
    bank_account_number: Mapped[str | None] = mapped_column(String(30))
    bank_account_name: Mapped[str | None] = mapped_column(String(100))
    order_slots: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=5)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"), onupdate=datetime.utcnow)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    apartment: Mapped["Apartment | None"] = relationship("Apartment", foreign_keys=[apartment_id], lazy="selectin")

    # relationships
    created_orders: Mapped[list["Order"]] = relationship("Order", foreign_keys="Order.creator_id", back_populates="creator", lazy="noload")
    shipped_orders: Mapped[list["Order"]] = relationship("Order", foreign_keys="Order.shipper_id", back_populates="shipper", lazy="noload")
    gold_transactions: Mapped[list["GoldLedger"]] = relationship("GoldLedger", back_populates="user", lazy="noload")
    device_tokens: Mapped[list["DeviceToken"]] = relationship("DeviceToken", back_populates="user", lazy="noload")


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    token: Mapped[str] = mapped_column(String, nullable=False)
    platform: Mapped[str] = mapped_column(String(10), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))

    user: Mapped["User"] = relationship("User", back_populates="device_tokens")


class ShipperAlert(Base):
    """Per-user opt-in for FCM push when a new pending order matches their browse filter."""

    __tablename__ = "shipper_alerts"

    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    min_gold: Mapped[float | None] = mapped_column(Numeric(8, 2), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))

    locations: Mapped[list["ShipperAlertLocation"]] = relationship(
        "ShipperAlertLocation",
        primaryjoin="ShipperAlert.user_id == ShipperAlertLocation.user_id",
        foreign_keys="ShipperAlertLocation.user_id",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class ShipperAlertLocation(Base):
    """One row per (user, apartment, building?, floor?) location filter."""

    __tablename__ = "shipper_alert_locations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    apartment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("apartments.id", ondelete="CASCADE"), nullable=False
    )
    building: Mapped[str | None] = mapped_column(String(20))   # NULL = any building
    floor: Mapped[int | None] = mapped_column(SmallInteger)    # NULL = any floor


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    token_hash: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    device_id: Mapped[str | None] = mapped_column(String)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=text("NOW()"))
