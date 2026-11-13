import pytest

from scripts import check_ebay

BASE = "https://api.ebay.com"


@pytest.mark.parametrize("analytics_status", [200, 403])
def test_check_uses_verified_category_and_prints_diagnostics(
    respx_mock, settings, payload, monkeypatch, capsys, analytics_status
):
    monkeypatch.setattr(check_ebay, "Settings", lambda: settings)
    respx_mock.post(f"{BASE}/identity/v1/oauth2/token").respond(json=payload("token"))
    respx_mock.get(
        f"{BASE}/developer/analytics/v1_beta/rate_limit/", params={"api_name": "browse"}
    ).respond(analytics_status, json=payload("analytics"))
    taxonomy = f"{BASE}/commerce/taxonomy/v1"
    respx_mock.get(
        f"{taxonomy}/get_default_category_tree_id", params={"marketplace_id": "EBAY_DE"}
    ).respond(json=payload("taxonomy_tree"))
    for query in ("PlayStation 5 console", "Xbox Series X console"):
        respx_mock.get(
            f"{taxonomy}/category_tree/77/get_category_suggestions", params={"q": query}
        ).respond(json=payload("taxonomy_suggestions"))
    search = respx_mock.get(
        f"{BASE}/buy/browse/v1/item_summary/search",
        params={
            "q": "ps5",
            "category_ids": "999991",
            "filter": "conditionIds:{7000},deliveryCountry:HU,itemLocationRegion:EUROPEAN_UNION",
            "limit": "10",
        },
    ).respond(json=payload("browse"))

    assert check_ebay.main() == 0
    assert search.called
    headers = search.calls.last.request.headers
    assert headers["X-EBAY-C-MARKETPLACE-ID"] == "EBAY_DE"
    assert headers["X-EBAY-C-ENDUSERCTX"] == "contextualLocation=country=HU"
    assert headers["Authorization"] == "Bearer fixture-application-token"
    output = capsys.readouterr().out
    if analytics_status == 200:
        assert "napi 1234; hátralévő hívások: 1230" in output
    else:
        assert "alkalmazástokennel nem érhető el (HTTP 403)" in output
    assert "999991; eltér" in output
    assert "Összes találat: 2" in output
    assert "Termék helye: DE\n" in output
    assert "Termék helye: GB — FIGYELEM: nem EU-tagállam" in output
    assert "Szállítás Magyarországra: Nem ismert" in output
    assert "Szállítás Magyarországra: 0 EUR" in output
    assert "Aktuális licit: 75.00 EUR" in output
    assert "Licitek száma: 0" in output
    assert "Aukció vége: 2026-12-31T12:00:00Z" in output
    assert "https://example.test/auction" in output
    assert "fixture-seller" not in output
    assert "56789" not in output
    assert "fixture-application-token" not in output
    assert "indított eBay API-hívások száma: 6" in output


def test_calculated_shipping_is_unknown():
    item = {"shippingOptions": [
        {"shippingCostType": "CALCULATED", "shippingCost": {"value": "0", "currency": "EUR"}}
    ]}
    assert check_ebay.shipping_cost(item) == "Nem ismert"
