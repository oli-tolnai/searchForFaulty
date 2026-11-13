import httpx
from pydantic import ValidationError

from app.adapters.ebay import EbayAdapter
from app.adapters.ebay_auth import redact
from app.config import Settings
from scripts.ebay_diagnostics import display

QUERIES = ("ps5", "playstation 5", "xbox series", "(ps5, playstation 5, xbox series)")


def main() -> int:
    try:
        settings = Settings()
    except ValidationError:
        print("Az eBay beállításai érvénytelenek.")
        return 1
    if settings.ebay_env != "production":
        print("A méréshez production környezet szükséges.")
        return 1

    results = []
    with httpx.Client(timeout=15.0) as client:
        adapter = EbayAdapter(client, settings)
        for query in QUERIES:
            result = adapter.search_country("DE", query=query)
            results.append(result)
            print(f"q={query}: total={display(result.total)}")
            if result.error:
                print(f"   Hiba: {result.error}")
            if result.warnings:
                print(f"   Figyelmeztetések: {result.warnings}")

    separate = {
        item.source_listing_id: item.title for result in results[:3] for item in result.listings
    }
    combined = {item.source_listing_id for item in results[3].listings}
    missing = separate.keys() - combined
    print(f"A három külön keresés {len(separate)} egyedi azonosítójából {len(separate) - len(missing)} közös.")
    print(f"A VAGY-mintából hiányzó címek ({len(missing)}):")
    secrets = (
        settings.ebay_client_id.get_secret_value().strip(),
        settings.ebay_client_secret.get_secret_value().strip(),
    )
    for item_id, title in separate.items():
        if item_id in missing:
            print(f"   - {redact(display(title), *secrets)}")
    return int(any(result.error for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
