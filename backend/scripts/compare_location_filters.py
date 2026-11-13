from collections import Counter
from dataclasses import dataclass

import httpx
from pydantic import ValidationError

from app.adapters.ebay_auth import EbayAuth, EbayAuthError
from app.config import Settings
from app.geography import EU_COUNTRIES
from scripts.ebay_diagnostics import (
    display,
    item_country,
    objects,
    print_warnings,
)

BASE_FILTER = "conditionIds:{7000},buyingOptions:{AUCTION|FIXED_PRICE},deliveryCountry:HU"
SEARCH_PATH = "/buy/browse/v1/item_summary/search"
VARIANTS = (
    ("A", "EBAY_DE", "itemLocationRegion:EUROPEAN_UNION"),
    ("B", "EBAY_DE", ""),
    ("C", "EBAY_DE", "itemLocationCountry:DE"),
    ("D", "EBAY_AT", "itemLocationCountry:AT"),
    ("E", "EBAY_FR", "itemLocationCountry:FR"),
    ("F", "EBAY_IT", "itemLocationCountry:IT"),
    ("G", "EBAY_DE", "itemLocationRegion:CONTINENTAL_EUROPE"),
)
HTTP_ERRORS = {
    400: "Az eBay elutasította a keresési paramétereket.",
    401: "Az eBay elutasította az alkalmazástokent.",
    403: "A kulcs nem fér hozzá ehhez a kereséshez.",
    429: "Az eBay korlátozta a hívásokat.",
}


@dataclass
class LocationCounts:
    countries: Counter[str]
    eu_count: int
    eu_ids: set[str]
    eu_without_id: int


def count_locations(items: list[dict]) -> LocationCounts:
    countries: Counter[str] = Counter()
    eu_count = eu_without_id = 0
    eu_ids: set[str] = set()
    for item in items:
        country = item_country(item)
        countries[country] += 1
        if country in EU_COUNTRIES:
            eu_count += 1
            item_id = item.get("itemId")
            if isinstance(item_id, str) and item_id.strip():
                eu_ids.add(item_id)
            else:
                eu_without_id += 1
    return LocationCounts(countries, eu_count, eu_ids, eu_without_id)


class SearchError(Exception):
    def __init__(self, message: str, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


def search(
    client: httpx.Client,
    settings: Settings,
    token: str,
    marketplace: str,
    location: str,
    *,
    query: str | None = "ps5",
    offset: int | None = None,
) -> dict:
    params: dict[str, str | int] = {
        "category_ids": "139971",
        "limit": 200,
        "filter": f"{BASE_FILTER},{location}" if location else BASE_FILTER,
    }
    if query is not None:
        params["q"] = query
    if offset is not None:
        params["offset"] = offset
    try:
        response = client.get(
            f"{settings.ebay_api_url}{SEARCH_PATH}",
            params=params,
            headers={
                "Authorization": f"Bearer {token}",
                "X-EBAY-C-MARKETPLACE-ID": marketplace,
                "X-EBAY-C-ENDUSERCTX": "contextualLocation=country=HU",
            },
        )
    except httpx.TimeoutException:
        raise SearchError("A kérés túllépte az időkorlátot.") from None
    except httpx.RequestError:
        raise SearchError("Hálózati hiba történt.") from None

    try:
        payload = response.json()
    except ValueError:
        payload = None
    if isinstance(payload, dict):
        print_warnings(
            payload,
            settings.ebay_client_id.get_secret_value().strip(),
            settings.ebay_client_secret.get_secret_value().strip(),
            token,
        )
    if not response.is_success:
        message = HTTP_ERRORS.get(response.status_code, "Sikertelen keresés.")
        errors = objects(payload.get("errors")) if isinstance(payload, dict) else []
        codes = [str(error["errorId"]) for error in errors if type(error.get("errorId")) is int]
        detail = f" eBay-hibakód: {', '.join(codes)}." if codes else ""
        raise SearchError(f"HTTP {response.status_code}. {message}{detail}", response.status_code)
    if not isinstance(payload, dict):
        raise SearchError("Az eBay válasza nem értelmezhető.")
    return payload


def compare(client: httpx.Client, settings: Settings) -> int:
    auth = EbayAuth(client, settings)
    rows = []
    country_ids: set[str] = set()
    successful = 0
    for label, marketplace, location in VARIANTS:
        print(f"\n{label}. {marketplace} — {location or 'helyszűrő nélkül'}")
        try:
            token = auth.get_token()
            payload = search(client, settings, token.value, marketplace, location)
        except EbayAuthError as error:
            print(f"   Tokenhiba: {error}")
            return 1
        except SearchError as error:
            print(f"   {error}")
            rows.append(f"{label} | {marketplace} | — | — | — | — | Hiba")
            continue

        successful += 1
        items = objects(payload.get("itemSummaries"))
        counts = count_locations(items)
        total = display(payload.get("total"))
        distribution = ", ".join(
            f"{country}: {count}"
            for country, count in sorted(counts.countries.items(), key=lambda pair: (-pair[1], pair[0]))
        )
        print(f"   API szerinti összes találat (total): {total}. Visszakapott tételek: {len(items)}.")
        print(f"   Országeloszlás: {distribution or 'nincs tétel'}.")
        print(f"   EU-s tételek: {counts.eu_count}. Egyedi EU-s itemId-k: {len(counts.eu_ids)}.")
        if counts.eu_without_id:
            print(f"   Azonosító nélküli EU-s tételek: {counts.eu_without_id}.")
        rows.append(
            f"{label} | {marketplace} | {total} | {len(items)} | {counts.eu_count} "
            f"| {len(counts.eu_ids)} | Siker"
        )
        if label in ("C", "D", "E", "F"):
            country_ids.update(counts.eu_ids)

    print("\nÖsszesítő táblázat (változatonként egy oldal):")
    print("Változat | Piactér | Total | Visszakapott | EU-s | Egyedi EU-s | Állapot")
    print("\n".join(rows))
    if successful < len(VARIANTS):
        print("A sikertelen változatok nem számítanak bele az egyedi tételek összesítésébe.")
    print(f"C+D+E+F sikeres válaszaiban az egyedi EU-s itemId-k száma együtt: {len(country_ids)}.")
    return 0 if successful == len(VARIANTS) else 1


def main() -> int:
    calls = 0

    def count_request(_request: httpx.Request) -> None:
        nonlocal calls
        calls += 1

    try:
        try:
            settings = Settings()
        except ValidationError:
            print("Az EBAY_ENV értéke csak production vagy sandbox lehet.")
            return 1
        if settings.ebay_env != "production":
            print("A helyszűrők méréséhez Production kulcs és production környezet szükséges.")
            return 1
        with httpx.Client(timeout=15.0, event_hooks={"request": [count_request]}) as client:
            return compare(client, settings)
    finally:
        print(f"Indított eBay API-hívások száma (tokenkéréssel együtt): {calls}.")


if __name__ == "__main__":
    raise SystemExit(main())
