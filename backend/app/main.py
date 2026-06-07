import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.api.v1.router import api_router
from app.config import get_settings
from app.core.limiter import limiter
from app.core.redis import close_redis
from app.database import engine
from app.tasks.expiry import start_scheduler, stop_scheduler

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── Startup ──
    logger.info("Starting ShopHo API (env=%s)", settings.app_env)
    start_scheduler()
    yield
    # ── Shutdown ──
    stop_scheduler()
    await close_redis()
    await engine.dispose()
    logger.info("ShopHo API shut down cleanly")


app = FastAPI(
    title="ShopHo API",
    version="1.0.0",
    description="Kết nối người mua/ship hộ trong khu căn hộ",
    lifespan=lifespan,
    docs_url="/docs" if settings.app_env == "development" else None,
    redoc_url=None,
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── Middleware ───────────────────────────────────────────────

app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routes ──────────────────────────────────────────────────

app.include_router(api_router)


@app.get("/health", tags=["infra"])
async def health():
    return {"status": "ok"}


# ── Static pages (clean URLs, no .html needed) ───────────────

_STATIC = "/app/static"

@app.get("/melo-landing")
@app.get("/melo-landing.html")
async def melo_landing():
    return FileResponse(f"{_STATIC}/melo-landing.html")

@app.get("/menu")
@app.get("/menu.html")
async def menu_page():
    return FileResponse(f"{_STATIC}/menu.html")

@app.get("/melo-privacy")
@app.get("/melo-privacy.html")
async def melo_privacy():
    return FileResponse(f"{_STATIC}/melo-privacy.html")

# Serve all other static assets (images, icons, fonts…)
if os.path.isdir(_STATIC):
    app.mount("/", StaticFiles(directory=_STATIC), name="static")
