"""Firebase Cloud Messaging helper."""
import base64
import json
import logging
import os
import time
from datetime import timedelta
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)

_initialized = False


def _init() -> bool:
    global _initialized
    if _initialized:
        return True
    try:
        import firebase_admin
        from firebase_admin import credentials

        # Priority 1: base64-encoded JSON in env var (for Railway/cloud)
        b64 = os.environ.get("FIREBASE_SERVICE_ACCOUNT_B64")
        if b64:
            sa_dict = json.loads(base64.b64decode(b64).decode())
            cred = credentials.Certificate(sa_dict)
        else:
            # Priority 2: local file (for development)
            sa_path = os.path.abspath(
                os.path.join(os.path.dirname(__file__), "../../firebase-service-account.json")
            )
            if not os.path.exists(sa_path):
                logger.warning("FCM: no FIREBASE_SERVICE_ACCOUNT_B64 env var and no file at %s", sa_path)
                return False
            cred = credentials.Certificate(sa_path)

        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
        _initialized = True
        return True
    except Exception as e:
        logger.error("FCM init failed: %s", e)
        return False


_INVALID_TOKEN_ERRORS = {
    "registration-token-not-registered",
    "invalid-registration-token",
    "requested entity was not found",
}


async def send_push(
    tokens: list[str],
    title: str,
    body: str,
    data: dict | None = None,
    data_only: bool = False,
    ttl_seconds: int | None = None,
) -> list[str]:
    """Send FCM push notification to a list of device tokens.

    ttl_seconds overrides the default TTL (0 for data_only, 4 weeks otherwise).
    Pass ttl_seconds=40 for call notifications so brief offline periods don't
    cause the message to be dropped before the device reconnects.

    Returns a list of tokens that are permanently invalid and should be
    deleted from the database. Caller is responsible for the cleanup.
    """
    if not tokens:
        return []
    if not _init():
        return []
    try:
        from firebase_admin import messaging

        # TTL: caller-specified > data_only default (0) > notification default (4w)
        if ttl_seconds is not None:
            android_ttl = timedelta(seconds=ttl_seconds)
            apns_expiration = str(int(time.time()) + ttl_seconds)
        elif data_only:
            android_ttl = timedelta(seconds=0)
            apns_expiration = "0"
        else:
            android_ttl = timedelta(weeks=4)
            apns_expiration = ""

        use_apns_data_config = data_only or ttl_seconds is not None

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=None if data_only else messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(
                priority="high",
                ttl=android_ttl,
            ),
            apns=messaging.APNSConfig(
                headers={
                    "apns-priority": "10",
                    "apns-expiration": apns_expiration,
                },
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(content_available=True),
                ),
            ) if use_apns_data_config else None,
        )
        resp = messaging.send_each_for_multicast(message)
        logger.info("FCM sent %d/%d success (data_only=%s)", resp.success_count, len(tokens), data_only)

        stale: list[str] = []
        for i, r in enumerate(resp.responses):
            if not r.success:
                err_str = str(r.exception).lower()
                is_stale = any(e in err_str for e in _INVALID_TOKEN_ERRORS)
                if is_stale:
                    stale.append(tokens[i])
                    logger.info("FCM stale token pruned: %s…", tokens[i][:12])
                else:
                    logger.warning("FCM token[%d] failed: %s", i, r.exception)
        return stale
    except Exception as e:
        logger.error("FCM send failed: %s", e)
        return []


async def prune_stale_tokens(db: "AsyncSession", stale: list[str]) -> None:
    """Delete permanently-invalid FCM tokens from the database."""
    if not stale:
        return
    from sqlalchemy import delete
    from app.models.user import DeviceToken
    await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(stale)))
    await db.commit()
