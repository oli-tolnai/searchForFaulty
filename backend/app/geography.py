EU_COUNTRIES = frozenset({
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE",
    "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
})


def item_country(item: dict) -> str | None:
    location = item.get("itemLocation")
    country = location.get("country") if isinstance(location, dict) else None
    if isinstance(country, str) and len(country) == 2 and country.isascii() and country.isalpha():
        return country.upper()
    return None
