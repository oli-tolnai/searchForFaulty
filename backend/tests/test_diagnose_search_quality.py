import pytest

from app.services.model_detection import explain_model
from scripts.diagnose_search_quality import coverage, raw_shipping


def test_coverage_uses_union_and_deduplicates_ids(payload):
    samples = payload("query_coverage")
    reference = set(samples["ps5"]) | set(samples["xbox series"])
    assert len(reference) == 3
    assert coverage(reference, set(samples["ps5"])) == (2, set())
    assert coverage(reference, set(samples["(ps5,xbox)"])) == (2, {"fixture-xbox-one"})
    assert coverage(reference, set(samples["(ps5, xbox)"])) == (2, {"fixture-xbox-360"})
    assert coverage(reference, set()) == (0, set())


@pytest.mark.parametrize(
    ("title", "reason"),
    [
        ("PS5 controller", "„controller”"),
        ("Xbox Series X / Series S", "Series X és Series S"),
        ("PS5 CFI-2016A Pro", "Pro, Slim"),
        ("PS5 CFI-1016A Digital", "Disc és Digital"),
        ("PlayStation 5", "nem azonosítják"),
        ("PlayStation 4", "Nincs felismert"),
    ],
)
def test_explanation_identifies_the_rule_that_fired(title, reason):
    assert reason in explain_model(title)[1]


def test_raw_shipping_distinguishes_absent_and_empty_fields():
    assert raw_shipping({}, ()) == "hiányzik"
    assert raw_shipping({"shippingOptions": []}, ()) == "[]"
