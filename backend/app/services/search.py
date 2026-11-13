from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from decimal import Decimal
from threading import Lock

from app.adapters.ebay import BrowseError, EbayAdapter
from app.geography import EU_COUNTRIES
from app.models import (
    CountryStatus,
    ItemType,
    Listing,
    QueryStatus,
    SearchFilters,
    SearchResponse,
    ShippingTypeCounts,
    UnknownShippingBreakdown,
)

MAX_RUN_CALLS = 59
BROWSE_DAILY_LIMIT = 5000


class DailyCalls:
    def __init__(self):
        self._lock = Lock()
        self._day = None
        self._total = 0
        self._browse = 0

    def record(self, kind: str | None = None) -> tuple[int, int]:
        with self._lock:
            today = datetime.now(UTC).date()
            if self._day != today:
                self._day, self._total, self._browse = today, 0, 0
            if kind is not None:
                self._total += 1
                self._browse += kind == "browse"
            return self._total, self._browse


class SearchService:
    def __init__(self, adapter: EbayAdapter):
        self.adapter = adapter
        self.daily = DailyCalls()
        # Share the four workers between simultaneous API requests.
        self.pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="ebay")

    def close(self) -> None:
        self.pool.shutdown()

    def search(self, filters: SearchFilters) -> SearchResponse:
        searched_at = datetime.now(UTC)
        countries = self.adapter.settings.ebay_countries
        queries = self.adapter.settings.ebay_search_queries
        calls = 0
        first_pages_left = len(countries) * len(queries)
        # Always leave room for each configured first page and an initial token.
        run_limit = max(MAX_RUN_CALLS, first_pages_left + 1)
        lock = Lock()

        def count_call(kind: str, first_page: bool) -> None:
            nonlocal calls, first_pages_left
            with lock:
                reserved = first_pages_left - int(first_page)
                if calls + 1 + reserved > run_limit:
                    raise BrowseError("A keresés elérte a futásonkénti híváskeretet.")
                first_pages_left = reserved
                calls += 1
                self.daily.record(kind)

        futures = {
            (country, query): self.pool.submit(
                self.adapter.search_country, country, query=query, count_call=count_call
            )
            for country in countries for query in queries
        }
        states = []
        candidates: dict[tuple[str, str], Listing] = {}
        filtered_non_eu = 0
        for country in countries:
            query_states = []
            for query in queries:
                result = futures[country, query].result()
                filtered_non_eu += result.filtered_non_eu
                query_states.append(QueryStatus(
                    query=query, status="error" if result.error else "success",
                    error=result.error, warnings=result.warnings, count=len(result.listings),
                ))
                for item in result.listings:
                    if item.item_country not in EU_COUNTRIES:
                        filtered_non_eu += 1
                        continue
                    if item.status == "ACTIVE":
                        candidates.setdefault((item.source, item.source_listing_id), item)
            failures = sum(state.status == "error" for state in query_states)
            status = "error" if failures == len(query_states) else "partial" if failures else "success"
            states.append(CountryStatus(country=country, status=status, queries=query_states))

        now = datetime.now(UTC)
        known_shipping = []
        unknown_shipping = []
        type_counts: dict[ItemType, int] = dict.fromkeys(
            ("console", "console_bundle", "mainboard", "not_console", "unsupported_model", "needs_review"), 0
        )
        for item in candidates.values():
            if item.end_time is not None and item.end_time <= now:
                continue
            type_counts[item.item_type] += 1
            if item.item_type in {"not_console", "unsupported_model"}:
                continue
            if item.item_type == "mainboard" and not filters.include_mainboards:
                continue
            if not matches(item, filters, now):
                continue
            target = unknown_shipping if item.shipping_cost is None else known_shipping
            target.append(item)
        known_shipping.sort(key=lambda item: (item.total_price is None, item.total_price or Decimal(0)))
        unknown_shipping.sort(key=lambda item: (item.effective_price is None, item.effective_price or Decimal(0)))
        all_failed = all(state.status == "error" for state in states)
        has_errors = any(state.status != "success" for state in states)
        daily, browse = self.daily.record()
        return SearchResponse(
            status="error" if all_failed else "partial" if has_errors else "success",
            listings=known_shipping, unknown_shipping=unknown_shipping, countries=states,
            unknown_shipping_breakdown=shipping_breakdown(unknown_shipping),
            filtered_non_eu=filtered_non_eu, api_calls=calls, daily_api_calls=daily,
            item_type_counts=type_counts,
            daily_browse_calls=browse, searched_at=searched_at,
            quota_warning="Az eBay napi Browse-kerete közel van a kimerüléshez."
            if browse >= BROWSE_DAILY_LIMIT * 0.9 else None,
        )


def shipping_breakdown(items: list[Listing]) -> UnknownShippingBreakdown:
    totals = ShippingTypeCounts()
    countries: dict[str, ShippingTypeCounts] = {}
    for item in items:
        country = countries.setdefault(item.item_country or "UNKNOWN", ShippingTypeCounts())
        if "AUCTION" in item.buying_options:
            totals.auction += 1
            country.auction += 1
        else:
            totals.fixed_price += 1
            country.fixed_price += 1
    return UnknownShippingBreakdown(by_buying_type=totals, by_country=countries)


def matches(item: Listing, filters: SearchFilters, now: datetime) -> bool:
    if item.status != "ACTIVE" or (item.end_time is not None and item.end_time <= now):
        return False
    if filters.buying_options == "auction" and "AUCTION" not in item.buying_options:
        return False
    if filters.buying_options == "fixed" and "FIXED_PRICE" not in item.buying_options:
        return False
    model = item.console_model
    family = model.removesuffix(" Disc").removesuffix(" Digital")
    if model == "PS5 Digital":
        family = "PS5 (változat nem ismert)"
    if filters.console_models and not ({model, family} & set(filters.console_models)):
        return False
    price = item.effective_price
    if filters.max_price is not None and (price is None or price > filters.max_price):
        return False
    if filters.max_total_price is not None and item.shipping_cost is not None:
        return item.total_price is not None and item.total_price <= filters.max_total_price
    return True
