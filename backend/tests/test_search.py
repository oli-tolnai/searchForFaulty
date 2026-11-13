from datetime import UTC, datetime
from decimal import Decimal

import httpx
import pytest
from fastapi.testclient import TestClient

from app.adapters.ebay import BROWSE_PATH, EbayAdapter, normalize_listing
from app.main import create_app
from app.services.model_detection import detect_model

BASE = "https://api.ebay.com"


def test_title_classification(payload):
    for title, expected in payload("model_titles"):
        assert detect_model(title) == expected, title


def test_listing_normalization(payload):
    now = datetime.now(UTC)
    auction, fixed, unknown, expired, *_ = payload("search")["itemSummaries"]
    result = normalize_listing(auction, now)
    assert result.price is None
    assert result.current_bid == Decimal(35)
    assert result.bid_count == 2
    assert result.total_price == Decimal(50)
    assert result.status == "ACTIVE"
    assert normalize_listing(expired, now).status == "ENDED"
    fixed_result = normalize_listing(fixed, now)
    assert fixed_result.price == Decimal(30)
    assert fixed_result.shipping_cost == Decimal(0)
    assert fixed_result.total_price == fixed_result.price
    assert "seller" not in fixed_result.model_dump()
    unknown_result = normalize_listing(unknown, now)
    assert unknown_result.shipping_cost is None
    assert unknown_result.total_price is None
    fixed["shippingOptions"][0]["shippingCostType"] = "CALCULATED"
    assert normalize_listing(fixed, now).shipping_cost is None
    auction.pop("itemEndDate")
    assert normalize_listing(auction, now).status == "UNKNOWN"


def test_adapter_retries_429_and_paginates_to_five_pages(respx_mock, settings, payload, caplog):
    respx_mock.post(f"{BASE}/identity/v1/oauth2/token").respond(json=payload("token"))
    pages = respx_mock.get(BASE + BROWSE_PATH).mock(side_effect=[
        httpx.Response(429), *[httpx.Response(200, json={"total": 1100}) for _ in range(5)],
    ])
    waits = []
    with httpx.Client() as client:
        result = EbayAdapter(client, settings, sleep=waits.append).search_country("DE")
    assert result.error is None
    assert result.total == 1100
    assert result.warnings == ["Az ország keresése elérte az ötoldalas korlátot."]
    assert waits == [1.0]
    assert [call.request.url.params["offset"] for call in pages.calls] == [
        "0", "0", "200", "400", "600", "800"
    ]
    assert "fixture-application-token" not in caplog.text


def test_api_partial_search_sorting_filters_and_call_counts(respx_mock, settings, payload, caplog):
    settings.ebay_countries = ("DE", "FR")
    token = respx_mock.post(f"{BASE}/identity/v1/oauth2/token").respond(json=payload("token"))
    sample = payload("search")

    def respond(request):
        assert request.headers["X-EBAY-C-MARKETPLACE-ID"] == "EBAY_DE"
        assert request.headers["X-EBAY-C-ENDUSERCTX"] == "contextualLocation=country=HU"
        assert request.url.params["q"] == "(ps5, playstation 5, xbox series)"
        filters = request.url.params["filter"].split(",")
        assert filters[:3] == [
            "conditionIds:{7000}", "buyingOptions:{AUCTION|FIXED_PRICE}", "deliveryCountry:HU"
        ]
        if filters[3] == "itemLocationCountry:DE":
            return httpx.Response(200, json=sample)
        assert filters[3] == "itemLocationCountry:FR"
        return httpx.Response(503)

    respx_mock.get(BASE + BROWSE_PATH).mock(side_effect=respond)
    with TestClient(create_app(settings)) as client:
        response = client.post("/api/search", json={"max_price": 40, "max_total_price": 50})
        assert response.status_code == 200
        result = response.json()
        assert result["status"] == "partial"
        assert result["api_calls"] == 3
        assert result["daily_api_calls"] == 3
        assert result["daily_browse_calls"] == 2
        assert result["filtered_non_eu"] == 2
        assert [item["source_listing_id"] for item in result["listings"]] == ["fixed", "auction"]
        assert [item["source_listing_id"] for item in result["unknown_shipping"]] == ["unknown-shipping"]
        german, french = result["countries"]
        assert german["status"] == "success"
        assert german["warnings"] == [{"errorId": 123, "message": "Fixture warning"}]
        assert french["status"] == "error"
        assert "503" in french["error"]
        assert "fixture-seller" not in response.text + caplog.text

        result = client.post("/api/search", json={
            "max_price": 35, "max_total_price": 35, "buying_options": "fixed",
            "console_models": ["PS5 Pro"],
        }).json()
        assert [item["source_listing_id"] for item in result["listings"]] == ["fixed"]
        assert not result["unknown_shipping"]
        assert result["api_calls"] == 2
        assert result["daily_api_calls"] == 5
    assert token.call_count == 1


def test_api_success_and_total_failure(respx_mock, settings, payload):
    settings.ebay_countries = ("DE",)
    respx_mock.post(f"{BASE}/identity/v1/oauth2/token").respond(json=payload("token"))
    respx_mock.get(BASE + BROWSE_PATH).mock(side_effect=[
        httpx.Response(200, json={"total": 0}),
        httpx.ReadTimeout("fixture timeout"),
    ])
    with TestClient(create_app(settings)) as client:
        assert client.post("/api/search").json()["status"] == "success"
        failed = client.post("/api/search", json={})
        assert failed.status_code == 502
        assert failed.json()["status"] == "error"
        assert "időkorlátot" in failed.json()["countries"][0]["error"]
        assert client.post("/api/search", json={"max_price": -1}).status_code == 422


@pytest.mark.parametrize(
    ("filters", "known", "unknown"),
    [
        ({"max_price": 34}, ["fixed"], []),
        ({"max_total_price": 49}, ["fixed"], ["unknown-shipping"]),
        ({"buying_options": "auction"}, ["auction"], []),
        ({"console_models": ["Xbox Series S"]}, [], ["unknown-shipping"]),
    ],
)
def test_filters_apply_independently(respx_mock, settings, payload, filters, known, unknown):
    settings.ebay_countries = ("DE",)
    respx_mock.post(f"{BASE}/identity/v1/oauth2/token").respond(json=payload("token"))
    respx_mock.get(BASE + BROWSE_PATH).respond(json=payload("search"))
    with TestClient(create_app(settings)) as client:
        result = client.post("/api/search", json=filters).json()
    assert [item["source_listing_id"] for item in result["listings"]] == known
    assert [item["source_listing_id"] for item in result["unknown_shipping"]] == unknown


def test_run_budget_leaves_room_for_every_country(respx_mock, settings, payload):
    assert len(settings.ebay_countries) == 27
    respx_mock.post(f"{BASE}/identity/v1/oauth2/token").respond(json=payload("token"))
    route = respx_mock.get(BASE + BROWSE_PATH).respond(json={"total": 1100})
    with TestClient(create_app(settings)) as client:
        result = client.post("/api/search", json={}).json()

    first_pages = [
        call.request.url.params["filter"].rsplit(":", 1)[1]
        for call in route.calls if call.request.url.params["offset"] == "0"
    ]
    assert sorted(first_pages) == sorted(settings.ebay_countries)
    assert result["status"] == "partial"
    assert result["api_calls"] == 49
    assert route.call_count == 48
