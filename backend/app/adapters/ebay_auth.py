import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

import httpx

from app.config import Settings

LOGGER = logging.getLogger(__name__)
SCOPE = "https://api.ebay.com/oauth/api_scope"
REFRESH_MARGIN = timedelta(minutes=5)


class EbayAuthError(Exception):
    pass


def redact(text: str, *secrets: str) -> str:
    for secret in sorted(filter(None, secrets), key=len, reverse=True):
        text = text.replace(secret, "[KITAKARVA]")
    return text


@dataclass(frozen=True)
class ApplicationToken:
    value: str = field(repr=False)
    expires_at: datetime


class EbayAuth:
    def __init__(
        self,
        client: httpx.Client,
        settings: Settings,
        *,
        now: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._client = client
        self._settings = settings
        self._now = now
        self._token: ApplicationToken | None = None

    def get_token(self) -> ApplicationToken:
        now = self._now()
        if self._token is not None and self._token.expires_at - now > REFRESH_MARGIN:
            return self._token

        client_id = self._settings.ebay_client_id.get_secret_value().strip()
        client_secret = self._settings.ebay_client_secret.get_secret_value().strip()
        if not client_id or not client_secret:
            raise EbayAuthError(
                "Hiányzik az eBay App ID vagy Cert ID. Töltsd ki a repó gyökerében lévő "
                ".env fájlban az EBAY_CLIENT_ID és EBAY_CLIENT_SECRET mezőket."
            )

        try:
            response = self._client.post(
                f"{self._settings.ebay_api_url}/identity/v1/oauth2/token",
                auth=(client_id, client_secret),
                data={"grant_type": "client_credentials", "scope": SCOPE},
                follow_redirects=False,
            )
        except httpx.TimeoutException:
            raise EbayAuthError("Az eBay tokenkérés túllépte az időkorlátot.") from None
        except httpx.RequestError:
            raise EbayAuthError("Hálózati hiba történt az eBay token kérésekor.") from None

        if response.status_code in (400, 401):
            raise EbayAuthError(
                f"Az eBay elutasította a hitelesítést (HTTP {response.status_code}). "
                "Ellenőrizd az App ID-t, a Cert ID-t és a kiválasztott környezetet."
            )
        if response.status_code == 429:
            raise EbayAuthError("Az eBay korlátozta a tokenkéréseket (HTTP 429). Próbáld később.")
        if not response.is_success:
            raise EbayAuthError(f"Az eBay tokenkérés sikertelen (HTTP {response.status_code}).")

        try:
            payload = response.json()
            token, lifetime = payload["access_token"], payload["expires_in"]
            if not isinstance(token, str) or not token or type(lifetime) is not int or lifetime <= 0:
                raise ValueError
            expires_at = now + timedelta(seconds=lifetime)
        except (ValueError, TypeError, KeyError, OverflowError):
            raise EbayAuthError("Az eBay tokenválasza hiányos vagy érvénytelen.") from None

        self._token = ApplicationToken(token, expires_at)
        LOGGER.debug("eBay application token refreshed.")
        return self._token
