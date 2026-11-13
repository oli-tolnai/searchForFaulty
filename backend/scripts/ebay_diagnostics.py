import json
from typing import Any

from app.adapters.ebay_auth import redact

UNKNOWN = "Nem ismert"
EU_COUNTRIES = {
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE",
    "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
}


def objects(value: Any) -> list[dict]:
    return [entry for entry in value if isinstance(entry, dict)] if isinstance(value, list) else []


def display(value: Any) -> str:
    if isinstance(value, str) and value.strip():
        return "".join(char if char.isprintable() else " " for char in value)
    return str(value) if type(value) is int else UNKNOWN


def item_country(item: dict) -> str:
    location = item.get("itemLocation")
    country = location.get("country") if isinstance(location, dict) else None
    if isinstance(country, str) and len(country) == 2 and country.isascii() and country.isalpha():
        return country.upper()
    return UNKNOWN


def print_warnings(payload: dict, *secrets: str) -> None:
    if "warnings" in payload:
        print("   eBay-figyelmeztetések (warnings):")
        print(redact(json.dumps(payload["warnings"], ensure_ascii=False, indent=2), *secrets))
