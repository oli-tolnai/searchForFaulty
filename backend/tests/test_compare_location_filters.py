from httpx import Response

from scripts import compare_location_filters as diagnostic


def test_country_counts_distinguish_rows_from_unique_eu_ids(payload):
    counts = diagnostic.count_locations(payload("location_filters")["itemSummaries"])
    assert counts.countries == {"DE": 2, "PL": 1, "FR": 1, "US": 1, "Nem ismert": 1}
    assert counts.eu_count == 4
    assert counts.eu_ids == {"fixture-de", "fixture-pl"}
    assert counts.eu_without_id == 1


def test_compare_sends_all_variants_and_continues_after_http_error(
    respx_mock, settings, payload, monkeypatch, capsys
):
    monkeypatch.setattr(diagnostic, "Settings", lambda: settings)
    base = "https://api.ebay.com"
    respx_mock.post(f"{base}/identity/v1/oauth2/token").respond(json=payload("token"))
    search = respx_mock.get(f"{base}/buy/browse/v1/item_summary/search")
    fixture = payload("location_filters")
    expected = [
        ("EBAY_DE", "itemLocationRegion:EUROPEAN_UNION"),
        ("EBAY_DE", ""),
        ("EBAY_DE", "itemLocationCountry:DE"),
        ("EBAY_AT", "itemLocationCountry:AT"),
        ("EBAY_FR", "itemLocationCountry:FR"),
        ("EBAY_IT", "itemLocationCountry:IT"),
        ("EBAY_DE", "itemLocationRegion:CONTINENTAL_EUROPE"),
    ]

    def respond(request):
        if request.headers["X-EBAY-C-MARKETPLACE-ID"] == "EBAY_AT":
            return Response(400, json=fixture)
        return Response(200, json=fixture)

    search.mock(side_effect=respond)
    assert diagnostic.main() == 1
    assert search.call_count == len(expected)
    for call, (marketplace, location) in zip(search.calls, expected, strict=True):
        request = call.request
        assert request.headers["X-EBAY-C-MARKETPLACE-ID"] == marketplace
        assert request.headers["X-EBAY-C-ENDUSERCTX"] == "contextualLocation=country=HU"
        assert request.headers["Authorization"] == "Bearer fixture-application-token"
        filters = ["conditionIds:{7000}", "buyingOptions:{AUCTION|FIXED_PRICE}", "deliveryCountry:HU"]
        if location:
            filters.append(location)
        assert dict(request.url.params) == {
            "q": "ps5", "category_ids": "139971", "limit": "200", "filter": ",".join(filters)
        }

    output = capsys.readouterr().out
    assert "HTTP 400. Az eBay elutasította a keresési paramétereket." in output
    assert "G | EBAY_DE | 12 | 6 | 4 | 2 | Siker" in output
    assert '"value": "fixture"' in output
    assert "egyedi EU-s itemId-k száma együtt: 2." in output
    assert "tokenkéréssel együtt): 8." in output
    assert "fixture-seller" not in output
    assert "fixture-de" not in output
