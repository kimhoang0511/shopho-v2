import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr


class _BuildingBrief(BaseModel):
    name: str
    model_config = {"from_attributes": True}


class ApartmentBrief(BaseModel):
    id: uuid.UUID
    name: str
    address: str
    image_url: str | None = None
    buildings: list[_BuildingBrief] = []
    model_config = {"from_attributes": True}


class UserProfile(BaseModel):
    id: uuid.UUID
    username: str
    display_name: str | None
    avatar_url: str | None
    apartment_id: uuid.UUID | None
    apartment: ApartmentBrief | None
    apt_building: str | None
    apt_floor: int | None
    apt_room: str | None
    bank_code: str | None = None
    bank_account_number: str | None = None
    bank_account_name: str | None = None
    order_slots: int
    is_verified: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    display_name: str | None = None
    apartment_id: uuid.UUID | None = None
    apt_building: str | None = None
    apt_floor: int | None = None
    apt_room: str | None = None
    phone: str | None = None
    email: EmailStr | None = None
    bank_code: str | None = None
    bank_account_number: str | None = None
    bank_account_name: str | None = None


