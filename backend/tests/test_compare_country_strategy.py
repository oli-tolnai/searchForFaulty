import pytest
from httpx import Response

from scripts import compare_country_strategy as diagnostic


def test_title_classification_and_item_id_overlap(payload):
    sample = payload("country_strategy")
    groups = {item["itemId"]: diagnostic.classify_title(item["title"]) for item in sample["itemSummaries"]}
    assert groups == {
        "fixture-ps5": "PS5",
        "fixture-playstation": "PS5",
        "fixture-series-x": "Xbox Series X|S",
        "fixture-series-s": "Xbox Series X|S",
        "fixture-other": "Egyéb",
    }
    ps5_ids = {item_id for item_id, group in groups.items() if group == "PS5"}
    baseline = {item["itemId"] for item in sample["baseline"]}
    assert diagnostic.compare_ids(baseline, ps5_ids) == (
        {"fixture-ps5"}, {"fixture-missing", "fixture-missing-ps3"}, {"fixture-playstation"}
    )


@pytest.mark.parametrize("reject_no_query", [False, True])
def test_measurement_limits_pages_and_compares_returned_items(
    respx_mock, settings, payload, monkeypatch, capsys, reject_no_query
):
    monkeypatch.setattr(diagnostic, "Settings", lambda: settings)
    base = "https://api.ebay.com"
    respx_mock.post(f"{base}/identity/v1/oauth2/token").respond(json=payload("token"))
    sample = payload("country_strategy")

    def respond(request):
        params = request.url.params
        country = params["filter"].rsplit(":", 1)[1]
        if country != "DE":
            return Response(200, json={"total": 0})
        if params.get("q") == "ps5":
            return Response(200, json={"total": 3, "itemSummaries": sample["baseline"]})
        if reject_no_query and "q" not in params:
            return Response(400)
        return Response(200, json={"total": sample["total"], "itemSummaries": sample["itemSummaries"]})

    route = respx_mock.get(f"{base}/buy/browse/v1/item_summary/search").mock(side_effect=respond)
    assert diagnostic.main() == 0
    requests = [call.request for call in route.calls]
    expected_marketplaces = [
        ("EBAY_DE", "FR"), ("EBAY_FR", "FR"), ("EBAY_DE", "IT"), ("EBAY_IT", "IT"),
        ("EBAY_DE", "AT"), ("EBAY_DE", "PL"), ("EBAY_DE", "NL"), ("EBAY_DE", "ES"),
        ("EBAY_DE", "BE"), ("EBAY_DE", "CZ"),
    ]
    assert len(requests) == 14 + reject_no_query
    for request, (marketplace, country) in zip(requests[:10], expected_marketplaces, strict=True):
        assert request.headers["X-EBAY-C-MARKETPLACE-ID"] == marketplace
        assert request.headers["X-EBAY-C-ENDUSERCTX"] == "contextualLocation=country=HU"
        assert dict(request.url.params) == {
            "category_ids": "139971",
            "limit": "200",
            "offset": "0",
            "q": "ps5",
            "filter": "conditionIds:{7000},buyingOptions:{AUCTION|FIXED_PRICE},deliveryCountry:HU,"
                      f"itemLocationCountry:{country}",
        }

    assert "q" not in requests[10].url.params
    category_requests = requests[10 + reject_no_query:-1]
    assert [request.url.params["offset"] for request in category_requests] == ["0", "200", "400"]
    assert [request.url.params.get("q") for request in category_requests] == [
        "konsole" if reject_no_query else None
    ] * 3
    assert requests[-1].url.params["q"] == "ps5"
    output = capsys.readouterr().out
    assert "Total: 900. Lekért oldalak: 3." in output
    assert "PS5 | 2" in output
    assert "Xbox Series X|S | 2" in output
    assert "Egyéb | 1" in output
    assert "3 itemId-jéből 1 van a PS5 csoportban" in output
    assert "PS5 nur in der Stichprobe" in output
    assert "PS3 nur in der Stichprobe" not in output
    assert "fixture-seller" not in output
    assert f"tokenkéréssel együtt): {15 + reject_no_query}." in output
