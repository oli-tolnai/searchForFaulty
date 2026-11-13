from datetime import UTC, datetime, timedelta
from urllib.parse import parse_qs

import httpx
import pytest

from app.adapters.ebay_auth import EbayAuth, EbayAuthError, redact
from app.config import Settings

TOKEN_URL = "https://api.ebay.com/identity/v1/oauth2/token"


def test_token_reused_until_five_minutes_before_expiry(respx_mock, settings, payload, caplog):
    route = respx_mock.post(TOKEN_URL).respond(json=payload("token"))
    now = datetime(2026, 1, 1, tzinfo=UTC)
    with httpx.Client() as client, caplog.at_level("DEBUG"):
        auth = EbayAuth(client, settings, now=lambda: now)
        first = auth.get_token()
        now += timedelta(minutes=115, seconds=-1)
        assert auth.get_token() is first
        assert route.call_count == 1
        now += timedelta(seconds=1)
        assert auth.get_token().expires_at == now + timedelta(hours=2)
        assert route.call_count == 2
    request = route.calls[0].request
    assert request.headers["Authorization"] == "Basic Zml4dHVyZS1pZDpmaXh0dXJlLXNlY3JldA=="
    assert parse_qs(request.content.decode()) == {
        "grant_type": ["client_credentials"],
        "scope": ["https://api.ebay.com/oauth/api_scope"],
    }
    assert "fixture-secret" not in caplog.text
    assert first.value not in caplog.text
    assert first.value not in repr(first)


@pytest.mark.parametrize(
    ("status", "message"),
    [(401, "Ellenőrizd az App ID-t"), (429, "korlátozta a tokenkéréseket")],
)
def test_http_errors(respx_mock, settings, status, message):
    respx_mock.post(TOKEN_URL).respond(status, text="fixture-secret")
    with httpx.Client() as client, pytest.raises(EbayAuthError, match=message) as exc:
        EbayAuth(client, settings).get_token()
    assert "fixture-secret" not in str(exc.value)


@pytest.mark.parametrize(
    ("error", "message"),
    [(httpx.ReadTimeout, "időkorlátot"), (httpx.ConnectError, "Hálózati hiba")],
)
def test_transport_errors(respx_mock, settings, error, message):
    respx_mock.post(TOKEN_URL).mock(side_effect=error("fixture-secret"))
    with httpx.Client() as client, pytest.raises(EbayAuthError, match=message):
        EbayAuth(client, settings).get_token()


def test_missing_keys_do_not_send_requests(respx_mock):
    with httpx.Client() as client, pytest.raises(EbayAuthError, match=r"Hiányzik.*\.env"):
        EbayAuth(client, Settings(_env_file=None)).get_token()
    assert not respx_mock.calls


def test_redaction():
    assert redact("secret=abc token=abc123", "abc", "abc123", "") == (
        "secret=[KITAKARVA] token=[KITAKARVA]"
    )
