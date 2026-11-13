from typing import Any

import httpx
from pydantic import ValidationError

from app.adapters.ebay_auth import EbayAuth, EbayAuthError, redact
from app.config import Settings
from app.geography import EU_COUNTRIES
from scripts.ebay_diagnostics import (
    UNKNOWN,
    display,
    item_country,
    objects,
    print_warnings,
)

MARKETPLACE = "EBAY_DE"
TAXONOMY = "/commerce/taxonomy/v1"
CONSOLE_NAMES = {"video game consoles", "konsolen", "videospielkonsolen", "videospiel-konsolen"}
BUYING_OPTIONS = {
    "FIXED_PRICE": "Fix ár",
    "AUCTION": "Aukció",
    "BEST_OFFER": "Ajánlattétel",
    "CLASSIFIED_AD": "Apróhirdetés",
}


class CheckError(Exception):
    pass


def money(amount: Any) -> str:
    if isinstance(amount, dict):
        value, currency = display(amount.get("value")), display(amount.get("currency"))
        if UNKNOWN not in (value, currency):
            return f"{value} {currency}"
    return UNKNOWN


def shipping_cost(item: dict) -> str:
    for option in objects(item.get("shippingOptions")):
        if option.get("shippingCostType") != "CALCULATED":
            cost = money(option.get("shippingCost"))
            if cost != UNKNOWN:
                return cost
    return UNKNOWN


def listing_lines(item: dict) -> list[str]:
    country = item_country(item)
    if country == UNKNOWN:
        country += " — az EU-tagság nem ellenőrizhető."
    elif country not in EU_COUNTRIES:
        country += " — FIGYELEM: nem EU-tagállam; a régiószűrő átengedte."

    options = item.get("buyingOptions")
    options = options if isinstance(options, list) else []
    types = [BUYING_OPTIONS.get(option, UNKNOWN) for option in options if isinstance(option, str)]
    price = money(item.get("price"))
    bid = money(item.get("currentBidPrice"))
    show_bid = bid != UNKNOWN and ("AUCTION" in options or price == UNKNOWN)
    price_line = f"Aktuális licit: {bid}" if show_bid else f"Ár: {price}"
    lines = [
        f"Cím: {display(item.get('title'))}",
        price_line,
        f"Hirdetéstípus: {', '.join(types) or UNKNOWN}",
    ]
    if "AUCTION" in options or any(
        item.get(key) is not None for key in ("currentBidPrice", "bidCount", "itemEndDate")
    ):
        lines.extend([
            f"Licitek száma: {display(item.get('bidCount'))}",
            f"Aukció vége: {display(item.get('itemEndDate'))}",
        ])
    return lines + [
        f"Termék helye: {country}",
        f"Szállítás Magyarországra: {shipping_cost(item)}",
        f"Hirdetés linkje: {display(item.get('itemWebUrl'))}",
    ]


def main() -> int:
    calls = 0

    def count_request(_request: httpx.Request) -> None:
        nonlocal calls
        calls += 1

    def check(client: httpx.Client, settings: Settings) -> int:
        auth = EbayAuth(client, settings)
        try:
            token = auth.get_token()
        except EbayAuthError as error:
            print(f"1. Token: {error}")
            print("2–4. A további ellenőrzések érvényes token nélkül kimaradtak.")
            return 1

        expires = token.expires_at.strftime("%Y-%m-%d %H:%M:%S UTC")
        print(f"1. Token: sikerült. Lejárat: {expires}.")
        if settings.ebay_env == "sandbox":
            print("2–4. Az éles keret, kategória és hirdetések ellenőrzéséhez Production kulcs kell.")
            return 0

        def get(path: str, *, params: dict, headers: dict | None = None) -> dict:
            nonlocal token
            token = auth.get_token()
            try:
                response = client.get(
                    f"{settings.ebay_api_url}{path}",
                    params=params,
                    headers={"Authorization": f"Bearer {token.value}", **(headers or {})},
                )
            except httpx.TimeoutException:
                raise CheckError("A kérés túllépte az időkorlátot.") from None
            except httpx.RequestError:
                raise CheckError("Hálózati hiba történt.") from None
            if not response.is_success:
                message = {
                    401: "Az alkalmazástokennel nem érhető el",
                    403: "Az alkalmazástokennel nem érhető el",
                    429: "Az eBay korlátozta a hívásokat",
                }.get(response.status_code, "Sikertelen kérés")
                raise CheckError(f"{message} (HTTP {response.status_code}).")
            try:
                payload = response.json()
                if isinstance(payload, dict):
                    return payload
            except ValueError:
                pass
            raise CheckError("Az eBay válasza nem értelmezhető.")

        try:
            limits = get("/developer/analytics/v1_beta/rate_limit/", params={"api_name": "browse"})
            rates = [
                rate
                for api in objects(limits.get("rateLimits"))
                if str(api.get("apiName", "")).casefold() == "browse"
                for resource in objects(api.get("resources"))
                if resource.get("name") == "buy.browse"
                for rate in objects(resource.get("rates"))
                if rate.get("timeWindow") == 86400
            ]
            if not rates:
                print("2. Hívásszám-keret: az eBay nem adott vissza napi Browse-keretet.")
            for rate in rates:
                print(
                    f"2. Hívásszám-keret: napi {display(rate.get('limit'))}; "
                    f"hátralévő hívások: {display(rate.get('remaining'))}."
                )
        except (CheckError, EbayAuthError) as error:
            print(f"2. Hívásszám-keret: {error} A kategória ellenőrzése folytatódik.")

        try:
            tree = get(
                f"{TAXONOMY}/get_default_category_tree_id", params={"marketplace_id": MARKETPLACE}
            )
            tree_id = tree.get("categoryTreeId")
            if not isinstance(tree_id, str) or not tree_id.isdecimal():
                raise CheckError("Az eBay nem adott érvényes kategóriafa-azonosítót.")
            categories = set()
            for query in ("PlayStation 5 console", "Xbox Series X console"):
                suggestions = get(
                    f"{TAXONOMY}/category_tree/{tree_id}/get_category_suggestions",
                    params={"q": query},
                )
                for suggestion in objects(suggestions.get("categorySuggestions")):
                    category = suggestion.get("category")
                    if not isinstance(category, dict):
                        continue
                    name, category_id = category.get("categoryName"), category.get("categoryId")
                    if (
                        isinstance(name, str) and name.strip().casefold() in CONSOLE_NAMES
                        and isinstance(category_id, str) and category_id.isdecimal()
                    ):
                        categories.add(category_id)
            if len(categories) != 1:
                raise CheckError("A Taxonomy API nem adott egyértelmű konzolkategóriát.")
            category_id = categories.pop()
        except (CheckError, EbayAuthError) as error:
            print(f"3. Kategória: {error}")
            print("4. Próbakeresés: kimaradt, mert a kategória nem ellenőrizhető.")
            return 1

        expected_id = "139971"
        comparison = (
            f"egyezik a tervben szereplő azonosítóval ({expected_id})"
            if category_id == expected_id
            else f"eltér a tervben szereplő azonosítótól ({expected_id})"
        )
        print(f"3. Kategória: Video Game Consoles (Játékkonzolok): {category_id}; {comparison}.")
        try:
            results = get(
                "/buy/browse/v1/item_summary/search",
                params={
                    "q": "ps5",
                    "category_ids": category_id,
                    "filter": (
                        "conditionIds:{7000},deliveryCountry:HU,itemLocationRegion:EUROPEAN_UNION,"
                        "buyingOptions:{AUCTION|FIXED_PRICE}"
                    ),
                    "limit": 10,
                },
                headers={
                    "X-EBAY-C-MARKETPLACE-ID": MARKETPLACE,
                    "X-EBAY-C-ENDUSERCTX": "contextualLocation=country=HU",
                },
            )
        except (CheckError, EbayAuthError) as error:
            print(f"4. Próbakeresés: {error}")
            return 1

        secrets = (
            settings.ebay_client_id.get_secret_value().strip(),
            settings.ebay_client_secret.get_secret_value().strip(),
            token.value,
        )
        print_warnings(results, *secrets)
        total = results.get("total")
        if type(total) is not int or total < 0:
            print("4. Próbakeresés: az eBay nem adott érvényes találatszámot.")
            return 1
        print(f"4. Próbakeresés: sikerült. Összes találat: {total}.")
        for index, item in enumerate(objects(results.get("itemSummaries"))[:10], 1):
            print(f"   {index}. találat:")
            for line in listing_lines(item):
                print("      " + redact(line, *secrets))
        return 0

    try:
        try:
            settings = Settings()
        except ValidationError:
            print("1. Token: az EBAY_ENV értéke csak production vagy sandbox lehet.")
            return 1
        with httpx.Client(timeout=15.0, event_hooks={"request": [count_request]}) as client:
            return check(client, settings)
    finally:
        print(f"5. Összegzés: indított eBay API-hívások száma: {calls}.")


if __name__ == "__main__":
    raise SystemExit(main())
