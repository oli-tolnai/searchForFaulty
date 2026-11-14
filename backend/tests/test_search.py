from datetime import UTC, datetime
from decimal import Decimal

import httpx
import pytest
from fastapi.testclient import TestClient

from app.adapters.ebay import BROWSE_PATH, EbayAdapter, normalize_listing
from app.main import create_app
from app.services.model_detection import classify_item

BASE = "https://api.ebay.com"


def test_title_classification(payload):
    for title, item_type, model, banned in payload("model_titles") + payload("diagnosed_titles"):
        result = classify_item(title)
        assert (result.item_type, result.console_model, result.is_banned) == (item_type, model, banned), title


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


def test_listing_date_prefers_creation_with_origin_fallback(payload):
    item = payload("search")["itemSummaries"][1]
    now = datetime.now(UTC)
    assert normalize_listing(item, now).listed_at is None
    item["itemOriginDate"] = "2026-01-01T00:00:00Z"
    item["itemCreationDate"] = "2026-02-01T00:00:00Z"
    assert normalize_listing(item, now).listed_at == datetime(2026, 2, 1, tzinfo=UTC)
    item["itemCreationDate"] = "invalid"
    assert normalize_listing(item, now).listed_at == datetime(2026, 1, 1, tzinfo=UTC)


@pytest.mark.parametrize(
    ("title", "expected"),
    [
        ("Sony PlayStation 5 PS5 Slim Digital Edition 1TB NEU 19% MwSt - Händler", True),
        ("PS5 Slim NEU Lüfter defekt", False),
        ("Xbox Series X sealed for parts", False),
        ("PS5 Slim Konsole", False),
    ],
)
def test_normalization_flags_new_titles_without_fault_signals(payload, title, expected):
    item = payload("search")["itemSummaries"][1]
    assert normalize_listing(dict(item, title=title), datetime.now(UTC)).possibly_not_faulty is expected


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
        assert request.headers["X-EBAY-C-ENDUSERCTX"] == "contextualLocation=country%3DHU"
        assert request.url.params["q"] in {"ps5", "xbox series"}
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
        assert result["api_calls"] == 5
        assert result["daily_api_calls"] == 5
        assert result["daily_browse_calls"] == 4
        assert result["filtered_non_eu"] == 4
        assert [item["source_listing_id"] for item in result["listings"]] == ["fixed", "auction"]
        assert [item["source_listing_id"] for item in result["unknown_shipping"]] == ["unknown-shipping"]
        assert result["unknown_shipping_breakdown"] == {
            "by_buying_type": {"auction": 0, "fixed_price": 1},
            "by_country": {"DE": {"auction": 0, "fixed_price": 1}},
        }
        german, french = result["countries"]
        assert german["status"] == "success"
        assert [query["query"] for query in german["queries"]] == ["ps5", "xbox series"]
        assert german["queries"][0]["warnings"] == [{"errorId": 123, "message": "Fixture warning"}]
        assert french["status"] == "error"
        assert all("503" in query["error"] for query in french["queries"])
        assert "fixture-seller" not in response.text + caplog.text

        result = client.post("/api/search", json={
            "max_price": 35, "max_total_price": 35, "buying_options": "fixed",
            "console_models": ["PS5 Pro"],
        }).json()
        assert [item["source_listing_id"] for item in result["listings"]] == ["fixed"]
        assert not result["unknown_shipping"]
        assert result["api_calls"] == 4
        assert result["daily_api_calls"] == 9
    assert token.call_count == 1


def test_api_success_and_total_failure(respx_mock, settings, payload):
    settings.ebay_countries = ("DE",)
    settings.ebay_search_queries = ("ps5",)
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
        assert "időkorlátot" in failed.json()["countries"][0]["queries"][0]["error"]
        assert client.post("/api/search", json={"max_price": -1}).status_code == 422


def test_unknown_shipping_breakdown_groups_auction_and_fixed_price_by_country(
    respx_mock, settings, payload
):
    settings.ebay_countries = ("DE",)
    respx_mock.post(f"{BASE}/identity/v1/oauth2/token").respond(json=payload("token"))
    sample = payload("search")
    auction = sample["itemSummaries"][0]
    auction.pop("shippingOptions")
    auction["itemLocation"]["country"] = "FR"
    auction["buyingOptions"].append("FIXED_PRICE")
    respx_mock.get(BASE + BROWSE_PATH).respond(json=sample)
    with TestClient(create_app(settings)) as client:
        result = client.post("/api/search", json={}).json()
    assert result["unknown_shipping_breakdown"] == {
        "by_buying_type": {"auction": 1, "fixed_price": 1},
        "by_country": {
            "DE": {"auction": 0, "fixed_price": 1},
            "FR": {"auction": 1, "fixed_price": 0},
        },
    }


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
        (call.request.url.params["filter"].rsplit(":", 1)[1], call.request.url.params["q"])
        for call in route.calls if call.request.url.params["offset"] == "0"
    ]
    assert sorted(first_pages) == sorted(
        (country, query) for country in settings.ebay_countries for query in settings.ebay_search_queries
    )
    assert result["status"] == "partial"
    assert result["api_calls"] == 59
    assert route.call_count == 58


def test_item_types_are_counted_once_and_mainboards_are_opt_in(respx_mock, settings, payload):
    settings.ebay_countries = ("DE",)
    respx_mock.post(f"{BASE}/identity/v1/oauth2/token").respond(json=payload("token"))
    base_item = payload("search")["itemSummaries"][1]
    titles = (
        "PS5 Slim Konsole", "Posten 4 PS5", "PS5 Slim EDM-040 Mainboard",
        "PS5 Box leer", "PS3 Konsole", "PS5 Xbox Series X",
    )
    items = [dict(base_item, itemId=str(index), title=title) for index, title in enumerate(titles)]

    def respond(request):
        if request.url.params["q"] == "xbox series":
            return httpx.Response(503)
        return httpx.Response(200, json={"total": len(items), "itemSummaries": items + items})

    respx_mock.get(BASE + BROWSE_PATH).mock(side_effect=respond)
    with TestClient(create_app(settings)) as client:
        default = client.post("/api/search", json={}).json()
        with_boards = client.post("/api/search", json={"include_mainboards": True}).json()
    assert default["status"] == default["countries"][0]["status"] == "partial"
    assert [query["status"] for query in default["countries"][0]["queries"]] == ["success", "error"]
    assert all(count == 1 for count in default["item_type_counts"].values())
    assert {item["item_type"] for item in default["listings"]} == {
        "console", "console_bundle", "needs_review"
    }
    assert {item["item_type"] for item in with_boards["listings"]} == {
        "console", "console_bundle", "needs_review", "mainboard"
    }
