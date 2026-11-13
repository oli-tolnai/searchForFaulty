import argparse
import json
from dataclasses import dataclass, field
from threading import Lock
from urllib.parse import quote

import httpx
from pydantic import ValidationError

from app.adapters.ebay import (
    BROWSE_PATH,
    MAX_PAGES,
    PAGE_SIZE,
    BrowseError,
    EbayAdapter,
    nonempty,
    sanitize_warning,
    shipping,
)
from app.adapters.ebay_auth import EbayAuthError, redact
from app.adapters.ebay_context import hu_context_header
from app.config import Settings
from app.geography import EU_COUNTRIES, item_country
from app.models import SearchFilters
from app.services.model_detection import classify_item
from app.services.search import SearchService
from scripts.compare_location_filters import BASE_FILTER
from scripts.ebay_diagnostics import display, objects

QUERIES = ("ps5", "xbox series", "(ps5,xbox)", "(ps5, xbox)", '(ps5,"xbox series")', "ps5 xbox")


def coverage(reference: set[str], found: set[str]) -> tuple[int, set[str]]:
    return len(reference & found), found - reference


@dataclass
class QuerySample:
    total: int | None = None
    titles: dict[str, str] = field(default_factory=dict)
    unknown_shipping: dict[str, str] = field(default_factory=dict)
    error: str | None = None
    truncated: bool = False
    known_shipping: set[str] = field(default_factory=set)
    shipping_warning: bool = False


def has_shipping_warning(payload: dict) -> bool:
    return any(str(warning.get("errorId")) == "11510" for warning in objects(payload.get("warnings")))


class Diagnostics:
    def __init__(self, adapter: EbayAdapter):
        self.adapter = adapter
        postal = adapter.settings.hu_postal_code
        self.postal_code = postal.get_secret_value() if postal else None
        self.secrets = (
            adapter.settings.ebay_client_id.get_secret_value().strip(),
            adapter.settings.ebay_client_secret.get_secret_value().strip(),
            self.postal_code or "",
        )

    def get(
        self, path: str, params: dict | None = None, *,
        context: str = "contextualLocation=country=HU",
    ) -> tuple[dict, tuple[str, ...]]:
        token = self.adapter.auth.get_token().value
        secrets = (*self.secrets, token)
        try:
            response = self.adapter.client.get(
                f"{self.adapter.settings.ebay_api_url}{path}",
                params=params,
                headers={
                    "Authorization": f"Bearer {token}",
                    "X-EBAY-C-MARKETPLACE-ID": "EBAY_DE",
                    "X-EBAY-C-ENDUSERCTX": context,
                },
                follow_redirects=False,
            )
        except httpx.TimeoutException:
            raise BrowseError("Az eBay-kérés túllépte az időkorlátot.") from None
        except httpx.RequestError:
            raise BrowseError("Hálózati hiba az eBay-kérésnél.") from None
        try:
            payload = response.json()
        except ValueError:
            payload = None
        if isinstance(payload, dict) and "warnings" in payload:
            warnings = sanitize_warning(payload["warnings"], secrets)
            print(f"   eBay warnings: {json.dumps(warnings, ensure_ascii=False)}")
        if not response.is_success:
            raise BrowseError(f"Az eBay-kérés sikertelen (HTTP {response.status_code}).")
        if not isinstance(payload, dict):
            raise BrowseError("Az eBay-válasz nem értelmezhető.")
        return payload, secrets

    def search(self, query: str, context: str = "contextualLocation=country=HU") -> QuerySample:
        sample = QuerySample()
        for page in range(MAX_PAGES):
            try:
                payload, secrets = self.get(BROWSE_PATH, {
                    "q": query,
                    "category_ids": "139971",
                    "filter": f"{BASE_FILTER},itemLocationCountry:DE",
                    "limit": PAGE_SIZE,
                    "offset": page * PAGE_SIZE,
                }, context=context)
                total = payload.get("total")
                if type(total) is not int or total < 0:
                    raise BrowseError("Hiányzó vagy érvénytelen találatszám.")
            except (BrowseError, EbayAuthError) as error:
                sample.error = str(error)
                break
            if sample.total is None:
                sample.total = total
            sample.shipping_warning |= has_shipping_warning(payload)
            for item in objects(payload.get("itemSummaries")):
                item_id = nonempty(item.get("itemId"))
                if item_id is None or item_country(item) != "DE" or item_id in sample.titles:
                    continue
                sample.titles[item_id] = redact(display(item.get("title")), *secrets)
                if shipping(item)[0] is not None:
                    sample.known_shipping.add(item_id)
                elif query == "ps5" and len(sample.unknown_shipping) < 10:
                    sample.unknown_shipping[item_id] = raw_shipping(item, secrets)
            if (page + 1) * PAGE_SIZE >= total:
                break
        else:
            sample.truncated = True
        return sample

    def compare_queries(self) -> tuple[QuerySample, bool]:
        print("1. Lekérdezésváltozatok — EBAY_DE, németországi tételek")
        samples = {}
        for query in QUERIES:
            print(f"   Lekérés: q={query}")
            samples[query] = self.search(query)
        reference = set(samples["ps5"].titles) | set(samples["xbox series"].titles)
        if any(samples[query].error or samples[query].truncated for query in QUERIES[:2]):
            print("A referencia részleges, a lefedettség csak a lekért tételekre vonatkozik.")
        print(f"Referencia (ps5 ∪ xbox series): {len(reference)} egyedi itemId.")
        for query, sample in samples.items():
            covered, extra = coverage(reference, set(sample.titles))
            print(
                f"q={query} | total={display(sample.total)} | lefedettség={covered}/{len(reference)} "
                f"| többlet={len(extra)}"
            )
            if sample.error:
                print(f"   Hiba: {sample.error}")
            if sample.truncated:
                print(f"   A minta elérte a {MAX_PAGES} oldalas korlátot.")
            extra_titles = [title for item_id, title in sample.titles.items() if item_id in extra]
            for title in extra_titles[:10]:
                print(f"   + {title}")
        return samples["ps5"], not any(sample.error for sample in samples.values())

    def compare_shipping(self, sample: QuerySample) -> bool:
        print("\n2. Ismeretlen szállítás — a német q=ps5 minta")
        known = errors = 0
        for index, (item_id, summary) in enumerate(sample.unknown_shipping.items(), 1):
            print(f"{index}. {sample.titles[item_id]}")
            print(f"   Summary shippingOptions: {summary}")
            try:
                item, secrets = self.get(f"/buy/browse/v1/item/{quote(item_id, safe='')}")
            except (BrowseError, EbayAuthError) as error:
                print(f"   getItem hiba: {error}")
                errors += 1
                continue
            print(f"   getItem shippingOptions: {raw_shipping(item, secrets)}")
            amount, currency = shipping(item)
            if amount is not None:
                known += 1
                print(f"   Magyarországi díj: {amount} {currency}")
            else:
                print("   Magyarországi díj: Nem ismert")
        print(f"A getItem {len(sample.unknown_shipping)} tételből {known} esetben adott ismert díjat.")
        return errors == 0

    def compare_shipping_headers(self) -> bool:
        print("\nSzállítási fejlécek összevetése — EBAY_DE, DE, q=ps5")
        variants = [
            ("A", "contextualLocation=country=HU"),
            ("B", hu_context_header()),
        ]
        if self.postal_code:
            variants.append(("C", hu_context_header(self.postal_code)))
        else:
            print("C kimarad: a HU_POSTAL_CODE nincs megadva.")
        baseline = self.search("ps5", variants[0][1])
        ids = list(baseline.unknown_shipping)
        print(f"Az A keresésből kiválasztott közös minta: {len(ids)} tétel.")
        success = not baseline.error and bool(ids)
        for name, context in variants:
            print(f"{name}: {redact(context, *self.secrets)}")
            sample = baseline if name == "A" else self.search("ps5", context)
            if sample.error:
                print(f"   Keresési hiba: {sample.error}")
                success = False
            summary_known = set(ids) & sample.known_shipping
            detail_known = set()
            warning = sample.shipping_warning
            errors = 0
            for item_id in ids:
                try:
                    item, _ = self.get(f"/buy/browse/v1/item/{quote(item_id, safe='')}", context=context)
                except (BrowseError, EbayAuthError) as error:
                    print(f"   getItem hiba: {error}")
                    errors += 1
                    continue
                warning |= has_shipping_warning(item)
                if shipping(item)[0] is not None:
                    detail_known.add(item_id)
            print(
                f"   Ismert díj: summary {len(summary_known)}/{len(ids)}, "
                f"getItem {len(detail_known)}/{len(ids)}, együtt {len(summary_known | detail_known)}/{len(ids)}."
            )
            print(f"   11510-es figyelmeztetés: {'igen' if warning else 'nem'}. getItem hibák: {errors}.")
            success &= not errors
        return success

    def explain_search(self) -> bool:
        settings = self.adapter.settings.model_copy(update={"ebay_countries": tuple(sorted(EU_COUNTRIES))})
        service_adapter = EbayAdapter(self.adapter.client, settings)
        service_adapter.auth = self.adapter.auth
        service = SearchService(service_adapter)
        print(f"\n3. Ellenőrzendő tételek — teljes keresés, {len(settings.ebay_countries)} ország")
        print(f"A jelenlegi q-k: {redact(display(', '.join(settings.ebay_search_queries)), *self.secrets)}")
        try:
            result = service.search(SearchFilters())
        finally:
            service.close()
        items = result.listings + result.unknown_shipping
        print(f"Állapot: {result.status} | Találatok: {len(items)} | Hívások: {result.api_calls}")
        for country in result.countries:
            for query in country.queries:
                if query.error:
                    print(f"   {country.country}, q={query.query}: {query.error}")
        group = [item for item in items if item.item_type == "needs_review"]
        print(f"Ellenőrzendő ({len(group)}):")
        for item in group:
            classification = classify_item(item.title)
            print(f"   - {redact(display(item.title), *self.secrets)} — {classification.reason}")
        return result.status == "success"


def raw_shipping(item: dict, secrets: tuple[str, ...]) -> str:
    if "shippingOptions" not in item:
        return "hiányzik"
    return json.dumps(sanitize_warning(item["shippingOptions"], secrets), ensure_ascii=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shipping-only", action="store_true", help="Csak a szállítási fejlécek mérése.")
    args = parser.parse_args()
    calls = 0
    lock = Lock()

    def count_request(_request: httpx.Request) -> None:
        nonlocal calls
        with lock:
            calls += 1

    try:
        settings = Settings()
        if settings.ebay_env != "production":
            print("A méréshez production környezet szükséges.")
            return 1
        with httpx.Client(timeout=15.0, event_hooks={"request": [count_request]}) as client:
            diagnostic = Diagnostics(EbayAdapter(client, settings))
            if args.shipping_only:
                return int(not diagnostic.compare_shipping_headers())
            sample, queries_ok = diagnostic.compare_queries()
            shipping_ok = diagnostic.compare_shipping(sample)
            headers_ok = diagnostic.compare_shipping_headers()
            search_ok = diagnostic.explain_search()
        return 0 if queries_ok and shipping_ok and headers_ok and search_ok else 1
    except ValidationError:
        print("Az eBay beállításai érvénytelenek.")
        return 1
    finally:
        print(f"\nÖsszes eBay API-hívás (tokenkéréssel együtt): {calls}.")


if __name__ == "__main__":
    raise SystemExit(main())
