from urllib.parse import quote


def hu_context_header(postal_code: str | None = None) -> str:
    location = "country=HU"
    if postal_code:
        location += f",zip={postal_code}"
    return "contextualLocation=" + quote(location, safe="")
