"""APNs VoIP Push — sends PushKit notifications to iOS devices.

VoIP push is the only reliable way to wake a killed iOS app for incoming calls.
Regular FCM/APNs silent push cannot guarantee waking a killed app on iOS.

Setup required (one-time):
  1. Apple Developer → Certificates, Identifiers & Profiles → Keys → Create key
     with "Apple Push Notifications service (APNs)" enabled.
  2. Download the .p8 file → place at path configured in APNS_KEY_PATH.
  3. Fill APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID in .env.
  4. Enable "Push Notifications" + "Background Modes > Voice over IP"
     capabilities in Xcode for the iOS target.
"""
import logging
import os
import time

import httpx
from jose import jwt

logger = logging.getLogger(__name__)

_APNS_PROD    = "https://api.push.apple.com"
_APNS_SANDBOX = "https://api.sandbox.push.apple.com"

_cached_key: str | None = None
_cached_key_path: str | None = None


def _load_key(path: str) -> str | None:
    global _cached_key, _cached_key_path
    if _cached_key and _cached_key_path == path:
        return _cached_key
    # Priority 1: env var (base64-encoded .p8 content for cloud deployments)
    b64 = os.environ.get("APNS_KEY_B64")
    if b64:
        import base64
        _cached_key = base64.b64decode(b64).decode()
        _cached_key_path = path
        return _cached_key
    # Priority 2: file path
    abs_path = os.path.abspath(path)
    if not os.path.exists(abs_path):
        logger.warning("[APNs] key file not found: %s", abs_path)
        return None
    with open(abs_path) as f:
        _cached_key = f.read()
    _cached_key_path = path
    return _cached_key


def _make_jwt(key_pem: str, key_id: str, team_id: str) -> str:
    return jwt.encode(
        {"iss": team_id, "iat": int(time.time())},
        key_pem,
        algorithm="ES256",
        headers={"kid": key_id},
    )


async def send_voip_push(voip_token: str, data: dict) -> None:
    """Send a VoIP PushKit notification to one iOS device token."""
    from app.config import get_settings
    s = get_settings()

    if not s.apns_key_id or not s.apns_team_id or not s.apns_bundle_id:
        logger.debug("[APNs] VoIP not configured — skipping")
        return

    key_pem = _load_key(s.apns_key_path)
    if not key_pem:
        return

    auth_token = _make_jwt(key_pem, s.apns_key_id, s.apns_team_id)
    host = _APNS_SANDBOX if s.app_env == "development" else _APNS_PROD

    headers = {
        "authorization": f"bearer {auth_token}",
        "apns-push-type": "voip",
        "apns-topic": f"{s.apns_bundle_id}.voip",
        "apns-priority": "10",
    }

    try:
        async with httpx.AsyncClient(http2=True, timeout=10) as client:
            resp = await client.post(
                f"{host}/3/device/{voip_token}",
                headers=headers,
                json=data,
            )
        if resp.status_code == 200:
            logger.info("[APNs] VoIP push sent → %s…", voip_token[:10])
        else:
            logger.error("[APNs] VoIP push failed %s: %s", resp.status_code, resp.text)
    except Exception as e:
        logger.error("[APNs] VoIP push error: %s", e)


async def send_voip_push_multi(voip_tokens: list[str], data: dict) -> None:
    """Send VoIP push to multiple tokens concurrently."""
    if not voip_tokens:
        return
    import asyncio
    await asyncio.gather(*(send_voip_push(t, data) for t in voip_tokens))
