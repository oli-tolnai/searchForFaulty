import logging
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import Decimal, InvalidOperation

import httpx
from pydantic import JsonValue

from app.adapters.ebay_auth import EbayAuth, EbayAuthError, redact
from app.config import Settings
from app.geography import EU_COUNTRIES, item_country
from app.models import Listing
from app.services.model_detection import detect_model

LOGGER = logging.getLogger(__name__)
PAGE_SIZE = 200
MAX_PAGES = 5
BROWSE_PATH = "/buy/browse/v1/item_summary/search"


def mapping(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def nonempty(value: object) -> str | None:
    return value if isinstance(value, str) and value.strip() else None


def money(value: object) -> tuple[Decimal | None, str | None]:
    data = mapping(value)
    currency = nonempty(data.get("currency"))
    try:
        amount = Decimal(str(data.get("value")))
    except InvalidOperation:
        return None, None
    if not currency or not amount.is_finite() or amount < 0:
        return None, None
    return amount, currency


def shipping(item: dict) -> tuple[Decimal | None, str | None]:
    options = item.get("shippingOptions")
    if not isinstance(options, list):
        return None, None
    for entry in options:
        if not isinstance(entry, dict):
            continue
        destination = mapping(entry.get("shipToLocationUsedForEstimate"))
        country = destination.get("country")
        if country is not None and country != "HU":
            continue
        if entry.get("shippingCostType") == "CALCULATED":
            return None, None
        return money(entry.get("shippingCost"))
    return None, None


def parse_end_time(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        result = datetime.fromisoformat(value)
    except ValueError:
        return None
    return result if result.tzinfo is not None else None


def normalize_listing(item: dict, checked_at: datetime) -> Listing | None:
    item_id = nonempty(item.get("itemId"))
    title = nonempty(item.get("title"))
    url = nonempty(item.get("itemWebUrl"))
    if not item_id or not title or not url:
        return None
    raw_options = item.get("buyingOptions")
    options = (
        [option for option in raw_options if isinstance(option, str)]
        if isinstance(raw_options, list) else []
    )
    auction = "AUCTION" in options
    amount, currency = money(item.get("currentBidPrice" if auction else "price"))
    shipping_cost, shipping_currency = shipping(item)
    total = None
    if amount is not None and shipping_cost is not None and currency == shipping_currency:
        total = amount + shipping_cost
    bid_count = item.get("bidCount")
    end = parse_end_time(item.get("itemEndDate"))
    if end is not None and end <= checked_at:
        status = "ENDED"
    elif (end is None and (auction or item.get("itemEndDate") is not None)) or not (
        auction or "FIXED_PRICE" in options
    ):
        status = "UNKNOWN"
    else:
        status = "ACTIVE"
    return Listing(
        source_listing_id=item_id, title=title, url=url,
        image_url=nonempty(mapping(item.get("image")).get("imageUrl")),
        console_model=detect_model(title), buying_options=options,
        price=None if auction else amount, current_bid=amount if auction else None,
        bid_count=bid_count if auction and type(bid_count) is int and bid_count >= 0 else None,
        currency=currency, shipping_cost=shipping_cost, shipping_currency=shipping_currency,
        total_price=total, item_country=item_country(item), end_time=end,
        condition=nonempty(item.get("condition")), status=status, last_checked_at=checked_at,
    )


def sanitize_warning(value: JsonValue, secrets: tuple[str, ...]) -> JsonValue:
    if isinstance(value, str):
        return redact(value, *secrets)
    if isinstance(value, list):
        return [sanitize_warning(part, secrets) for part in value]
    if isinstance(value, dict):
        if str(value.get("name", "")).casefold() in {"seller", "username", "feedbackscore", "feedbackpercentage"}:
            return "[KITAKARVA]"
        return {
            redact(key, *secrets): sanitize_warning(part, secrets)
            for key, part in value.items()
            if key.casefold() not in {"seller", "username", "feedbackscore", "feedbackpercentage"}
        }
    return value


class BrowseError(Exception):
    pass


@dataclass
class CountryResult:
    listings: list[Listing] = field(default_factory=list)
    warnings: list[JsonValue] = field(default_factory=list)
    error: str | None = None
    filtered_non_eu: int = 0
    total: int | None = None


class EbayAdapter:
    def __init__(
        self, client: httpx.Client, settings: Settings, *, sleep: Callable[[float], None] = time.sleep
    ):
        self.client = client
        self.settings = settings
        self.auth = EbayAuth(client, settings)
        self.sleep = sleep

    def search_country(
        self, country: str, *, query: str | None = None,
        count_call: Callable[[str, bool], None] | None = None,
    ) -> CountryResult:
        if country not in EU_COUNTRIES:
            raise ValueError("Csak EU-tagállamra lehet keresni.")
        result = CountryResult()
        try:
            for page in range(MAX_PAGES):
                total = self._page(country, query or self.settings.ebay_search_query, page, result, count_call)
                if result.total is None:
                    result.total = total
                if (page + 1) * PAGE_SIZE >= total:
                    break
            else:
                result.warnings.append("Az ország keresése elérte az ötoldalas korlátot.")
        except (BrowseError, EbayAuthError) as error:
            result.error = str(error)
        return result

    def _page(
        self, country: str, query: str, page: int, result: CountryResult,
        count_call: Callable[[str, bool], None] | None,
    ) -> int:
        token = self.auth.get_token(lambda: count_call("oauth", False) if count_call else None)
        for attempt in range(2):
            if count_call is not None:
                count_call("browse", page == 0 and attempt == 0)
            try:
                response = self.client.get(
                    f"{self.settings.ebay_api_url}{BROWSE_PATH}",
                    params={
                        "q": query, "category_ids": "139971", "limit": PAGE_SIZE,
                        "offset": PAGE_SIZE * page,
                        "filter": "conditionIds:{7000},buyingOptions:{AUCTION|FIXED_PRICE},"
                                  f"deliveryCountry:HU,itemLocationCountry:{country}",
                    },
                    headers={
                        "Authorization": f"Bearer {token.value}",
                        "X-EBAY-C-MARKETPLACE-ID": "EBAY_DE",
                        "X-EBAY-C-ENDUSERCTX": "contextualLocation=country=HU",
                    },
                    follow_redirects=False,
                )
            except httpx.TimeoutException:
                raise BrowseError("Az eBay keresése túllépte az időkorlátot.") from None
            except httpx.RequestError:
                raise BrowseError("Hálózati hiba az eBay keresésekor.") from None
            try:
                payload = mapping(response.json())
            except ValueError:
                payload = {}
            if "warnings" in payload:
                secrets = (
                    token.value, self.settings.ebay_client_id.get_secret_value().strip(),
                    self.settings.ebay_client_secret.get_secret_value().strip(),
                )
                warnings = sanitize_warning(payload["warnings"], secrets)
                LOGGER.warning("eBay Browse (%s) figyelmeztetések: %s", country, warnings)
                result.warnings.extend(warnings if isinstance(warnings, list) else [warnings])
            if response.status_code != 429 or attempt:
                break
            self.sleep(float(2 ** attempt))

        if response.status_code == 429:
            raise BrowseError("Az eBay korlátozta a hívásokat (HTTP 429).")
        if not response.is_success:
            raise BrowseError(f"Az eBay keresése sikertelen (HTTP {response.status_code}).")
        total = payload.get("total")
        items = payload.get("itemSummaries", [])
        if type(total) is not int or total < 0 or not isinstance(items, list):
            raise BrowseError("Az eBay keresési válasza hiányos vagy érvénytelen.")
        checked_at = datetime.now(UTC)
        for item in items:
            if not isinstance(item, dict):
                continue
            if item_country(item) not in EU_COUNTRIES:
                result.filtered_non_eu += 1
                continue
            listing = normalize_listing(item, checked_at)
            if listing is not None:
                result.listings.append(listing)
        return total
