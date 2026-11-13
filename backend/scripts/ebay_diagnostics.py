import json
from typing import Any

from app.adapters.ebay_auth import redact
from app.geography import item_country as parse_item_country

UNKNOWN = "Nem ismert"


def objects(value: Any) -> list[dict]:
    return [entry for entry in value if isinstance(entry, dict)] if isinstance(value, list) else []


def display(value: Any) -> str:
    if isinstance(value, str) and value.strip():
        return "".join(char if char.isprintable() else " " for char in value)
    return str(value) if type(value) is int else UNKNOWN


def item_country(item: dict) -> str:
    return parse_item_country(item) or UNKNOWN


def print_warnings(payload: dict, *secrets: str) -> None:
    if "warnings" in payload:
        print("   eBay-figyelmeztetések (warnings):")
        print(redact(json.dumps(payload["warnings"], ensure_ascii=False, indent=2), *secrets))
