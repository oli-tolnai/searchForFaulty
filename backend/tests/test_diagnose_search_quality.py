from app.adapters.ebay_context import hu_context_header
from scripts.diagnose_search_quality import coverage, raw_shipping


def test_coverage_uses_union_and_deduplicates_ids(payload):
    samples = payload("query_coverage")
    reference = set(samples["ps5"]) | set(samples["xbox series"])
    assert len(reference) == 3
    assert coverage(reference, set(samples["ps5"])) == (2, set())
    assert coverage(reference, set(samples["(ps5,xbox)"])) == (2, {"fixture-xbox-one"})
    assert coverage(reference, set(samples["(ps5, xbox)"])) == (2, {"fixture-xbox-360"})
    assert coverage(reference, set()) == (0, set())


def test_hu_context_encodes_the_location_but_not_the_header_key():
    assert hu_context_header() == "contextualLocation=country%3DHU"
    assert hu_context_header("1234") == "contextualLocation=country%3DHU%2Czip%3D1234"


def test_raw_shipping_distinguishes_absent_and_empty_fields():
    assert raw_shipping({}, ()) == "hiányzik"
    assert raw_shipping({"shippingOptions": []}, ()) == "[]"
