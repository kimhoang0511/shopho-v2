import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, field_validator, model_validator, Field

from app.models.order import OrderStatus, ShipLocationType, VALIDITY_OPTIONS


class OrderCreate(BaseModel):
    note: str
    gold_reward: float
    ship_location: ShipLocationType
    ship_building: str | None = None
    ship_floor: int | None = None
    ship_room: str | None = None
    validity_option: str

    @field_validator("note")
    @classmethod
    def note_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Ghi chú đơn không được để trống")
        return v

    @field_validator("gold_reward")
    @classmethod
    def gold_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("tiền công mua/ship phải lớn hơn 0")
        return v

    @field_validator("validity_option")
    @classmethod
    def validity_valid(cls, v: str) -> str:
        if v not in VALIDITY_OPTIONS:
            raise ValueError(f"validity_option phải là một trong: {list(VALIDITY_OPTIONS.keys())}")
        return v

    @field_validator("ship_floor")
    @classmethod
    def floor_positive(cls, v: int | None) -> int | None:
        if v is not None and v < 1:
            raise ValueError("Tầng phải >= 1")
        return v


class ImageInfo(BaseModel):
    id: uuid.UUID
    public_url: str
    sort_order: int

    model_config = {"from_attributes": True}


class UserInfo(BaseModel):
    id: uuid.UUID
    username: str
    display_name: str | None
    avatar_url: str | None

    model_config = {"from_attributes": True}


class ShipperInfo(UserInfo):
    bank_code: str | None = None
    bank_account_number: str | None = None
    bank_account_name: str | None = None


class OrderListItem(BaseModel):
    """Lightweight payload for the "find orders" list screen."""
    id: uuid.UUID
    creator_id: uuid.UUID
    note: str
    gold_reward: float
    ship_location: ShipLocationType
    ship_building: str | None
    ship_floor: int | None
    ship_room: str | None
    ship_apartment_name: str | None = None
    expires_at: datetime
    created_at: datetime
    images: list[ImageInfo] = []
    creator_building: str | None = None

    model_config = {"from_attributes": True}

    @model_validator(mode="before")
    @classmethod
    def extract_apartment_name(cls, data: Any) -> Any:
        if hasattr(data, "ship_apartment") and data.ship_apartment is not None:
            data.__dict__.setdefault("ship_apartment_name", data.ship_apartment.name)
        return data


class OrderResponse(BaseModel):
    """Full payload returned after create / get-by-id / accept."""
    id: uuid.UUID
    creator_id: uuid.UUID
    shipper_id: uuid.UUID | None
    note: str
    gold_reward: float
    ship_location: ShipLocationType
    ship_building: str | None
    ship_floor: int | None
    ship_room: str | None
    ship_apartment_name: str | None = None
    validity_option: str
    expires_at: datetime
    status: OrderStatus
    created_at: datetime
    updated_at: datetime
    accepted_at: datetime | None
    delivering_at: datetime | None = None
    completed_at: datetime | None
    estimated_minutes: int | None = None
    estimated_delivery_at: datetime | None = None
    total_gold: float | None = None
    images: list[ImageInfo] = []
    creator: UserInfo | None = None
    shipper: ShipperInfo | None = None
    min_proposed_gold: float | None = None

    model_config = {"from_attributes": True}

    @model_validator(mode="before")
    @classmethod
    def extract_apartment_name(cls, data: Any) -> Any:
        if hasattr(data, "ship_apartment") and data.ship_apartment is not None:
            data.__dict__.setdefault("ship_apartment_name", data.ship_apartment.name)
        return data


class ProposeGoldBody(BaseModel):
    proposed_gold: float = Field(..., ge=2)


class GoldProposalResponse(BaseModel):
    id: uuid.UUID
    order_id: uuid.UUID
    proposer_id: uuid.UUID
    proposer_name: str | None = None
    proposed_gold: float
    created_at: datetime

    model_config = {"from_attributes": True}

    @model_validator(mode="before")
    @classmethod
    def extract_proposer_name(cls, data: Any) -> Any:
        if hasattr(data, "proposer") and data.proposer is not None:
            data.__dict__.setdefault(
                "proposer_name",
                data.proposer.display_name or data.proposer.username,
            )
        return data


class MarketPriceItem(BaseModel):
    ship_location: ShipLocationType
    ship_building: str | None = None
    ship_floor: int | None = None
    ship_room: str | None = None
    gold_reward: float


class AcceptOrderBody(BaseModel):
    estimated_minutes: int | None = Field(None, ge=1, le=300)


class DeliverOrderBody(BaseModel):
    adjusted_gold: float | None = Field(None, ge=2)
    total_gold: float | None = Field(None, gt=0)


class CompleteOrderBody(BaseModel):
    bonus_gold: float | None = Field(None, gt=0)


class ReduceGoldBody(BaseModel):
    new_gold: float = Field(..., ge=2)


class AcceptOrderResponse(BaseModel):
    order: OrderResponse
