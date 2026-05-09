from fastapi import APIRouter

from app.api.v1 import admin, app_config, auth, chat, orders, slot_topup, topup, users, ws

api_router = APIRouter(prefix="/api/v1")

api_router.include_router(auth.router)
api_router.include_router(orders.router)
api_router.include_router(users.router)
api_router.include_router(ws.router)
api_router.include_router(admin.router)
api_router.include_router(chat.router)
api_router.include_router(app_config.router)
api_router.include_router(topup.router)
api_router.include_router(slot_topup.router)
