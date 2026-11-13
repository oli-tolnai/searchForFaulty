import re
from dataclasses import dataclass, field

import httpx
from pydantic import ValidationError

from app.adapters.ebay_auth import EbayAuth, EbayAuthError, redact
from app.config import Settings
from scripts.compare_location_filters import SearchError, search
from scripts.ebay_diagnostics import display, item_country, objects

COUNTRIES = ("FR", "IT", "AT", "PL", "NL", "ES", "BE", "CZ")
PAGE_SIZE = 200
MAX_PAGES = 3
PS5 = "PS5"
XBOX = "Xbox Series X|S"
OTHER = "Egyéb"
PS5_TITLE = re.compile(r"\b(?:ps5|playstation\s*5)\b", re.IGNORECASE)
XBOX_TITLE = re.compile(r"\bseries\s+[xs]\b", re.IGNORECASE)


def classify_title(title: str) -> str:
    if PS5_TITLE.search(title):
        return PS5
    if XBOX_TITLE.search(title):
        return XBOX
    return OTHER


def compare_ids(left: set[str], right: set[str]) -> tuple[set[str], set[str], set[str]]:
    return left & right, left - right, right - left


@dataclass
class Result:
    total: int | None = None
    pages: int = 0
    titles: dict[str, str] = field(default_factory=dict)
    error: SearchError | None = None

    def table_values(self) -> str:
        status = "Részleges" if self.error and self.pages else "Hiba" if self.error else "Siker"
        return f"{display(self.total)} | {self.pages} | {len(self.titles)} | {status}"


def fetch(
    client: httpx.Client,
    settings: Settings,
    auth: EbayAuth,
    marketplace: str,
    country: str,
    query: str | None,
) -> Result:
    result = Result()
    ignored = 0
    for offset in range(0, PAGE_SIZE * MAX_PAGES, PAGE_SIZE):
        try:
            token = auth.get_token()
            payload = search(
                client, settings, token.value, marketplace, f"itemLocationCountry:{country}",
                query=query, offset=offset,
            )
            total = payload.get("total")
            if type(total) is not int or total < 0:
                raise SearchError("Az eBay nem adott érvényes találatszámot.")
        except SearchError as error:
            result.error = error
            print(f"   Hiba az offset={offset} kérésnél: {error}")
            break

        if result.total is None:
            result.total = total
        result.pages += 1
        for item in objects(payload.get("itemSummaries")):
            item_id = item.get("itemId")
            if item_country(item) != country or not isinstance(item_id, str) or not item_id.strip():
                ignored += 1
                continue
            title = redact(
                display(item.get("title")),
                settings.ebay_client_id.get_secret_value().strip(),
                settings.ebay_client_secret.get_secret_value().strip(),
                token.value,
            )
            result.titles.setdefault(item_id, title)
        if offset + PAGE_SIZE >= total:
            break

    print(f"   Total: {display(result.total)}. Lekért oldalak: {result.pages}.")
    if ignored:
        print(f"   Kihagyott tételek eltérő vagy hiányzó ország, illetve hiányzó itemId miatt: {ignored}.")
    return result


def run(client: httpx.Client, settings: Settings) -> int:
    auth = EbayAuth(client, settings)
    rows: list[str] = []
    overlaps: list[str] = []
    errors = False

    def measure(test: int, marketplace: str, country: str, query: str | None) -> Result:
        label = f"q={query}" if query is not None else "q nélkül"
        print(f"\n{test}. teszt — {marketplace} + {country}, {label}")
        result = fetch(client, settings, auth, marketplace, country, query)
        rows.append(f"{test} | {marketplace} | {country} | {label} | {result.table_values()}")
        return result

    for country in COUNTRIES:
        german = measure(1, "EBAY_DE", country, "ps5")
        errors |= german.error is not None
        if country in ("FR", "IT"):
            local = measure(1, f"EBAY_{country}", country, "ps5")
            errors |= local.error is not None
            if german.pages and local.pages:
                common, german_only, local_only = compare_ids(set(german.titles), set(local.titles))
                overlaps.append(f"{country} | {len(common)} | {len(german_only)} | {len(local_only)}")
            else:
                overlaps.append(f"{country} | — | — | —")

    query = None
    category = measure(2, "EBAY_DE", "DE", query)
    if not category.pages and category.error and category.error.status_code is not None:
        print("   Új próba q=konsole értékkel.")
        query = "konsole"
        category = measure(2, "EBAY_DE", "DE", query)
    baseline = measure(2, "EBAY_DE", "DE", "ps5")
    errors |= category.error is not None or baseline.error is not None

    groups: dict[str, dict[str, str]] = {PS5: {}, XBOX: {}, OTHER: {}}
    for item_id, title in category.titles.items():
        groups[classify_title(title)][item_id] = title

    print("\nÖsszesítő (az itemId-k a lekért oldalakról származnak)")
    print("Teszt | Piactér | Ország | Keresés | Total | Oldalak | Egyedi tételek | Állapot")
    print("\n".join(rows))
    print("\n1. teszt — piacterek közti átfedés")
    print("Ország | Közös | Csak EBAY_DE | Csak a saját piactéren")
    print("\n".join(overlaps))

    print("\n2. teszt — címalapú besorolás")
    if not category.pages:
        print("A besoroláshoz nem érkezett értékelhető oldal.")
        return 1
    print(f"Minta: {'q nélkül' if query is None else 'q=konsole (tartalék keresés)'}.")
    print("Csoport | Egyedi tételek")
    for group, items in groups.items():
        print(f"{group} | {len(items)}")
    print("\nPéldacímek az Egyéb csoportból (legfeljebb 15):")
    for title in list(groups[OTHER].values())[:15]:
        print(f"   - {title}")

    if baseline.pages:
        common, outside_ps5, _ = compare_ids(set(baseline.titles), set(groups[PS5]))
        missing = outside_ps5 - category.titles.keys()
        missing_ps5_titles = [
            title
            for item_id, title in baseline.titles.items()
            if item_id in missing and classify_title(title) == PS5
        ]
        print(f"\nA q=ps5 minta {len(baseline.titles)} itemId-jéből {len(common)} van a PS5 csoportban.")
        print(f"A másik mintában megvan, de más csoportban: {len(outside_ps5) - len(missing)}.")
        print(f"A másik minta lekért oldalaiból hiányzó q=ps5 tételek: {len(missing)}.")
        print(f"Ebből PS5-nek besorolt tételek címei ({len(missing_ps5_titles)}):")
        for title in missing_ps5_titles:
            print(f"   - {title}")
    else:
        print("A q=ps5 összevetéshez nem érkezett értékelhető oldal.")
    return int(errors)


def main() -> int:
    calls = 0

    def count_request(_request: httpx.Request) -> None:
        nonlocal calls
        calls += 1

    try:
        settings = Settings()
        if settings.ebay_env != "production":
            print("A méréshez Production kulcs és production környezet szükséges.")
            return 1
        with httpx.Client(timeout=15.0, event_hooks={"request": [count_request]}) as client:
            return run(client, settings)
    except ValidationError:
        print("Az EBAY_ENV értéke csak production vagy sandbox lehet.")
        return 1
    except EbayAuthError as error:
        print(f"Tokenhiba: {error}")
        return 1
    finally:
        print(f"\nIndított eBay API-hívások száma (tokenkéréssel együtt): {calls}.")


if __name__ == "__main__":
    raise SystemExit(main())
