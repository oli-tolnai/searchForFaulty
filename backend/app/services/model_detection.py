import re

UNKNOWN = "Ellenőrzendő"
ACCESSORY = "Ellenőrzendő – lehet kiegészítő"
BUNDLE = "Csomag – ellenőrzendő"

CFI = re.compile(r"\bcfi[-\s]?(10|11|12|20|70)\d{2}([ab])?\b")
PS5 = re.compile(r"\b(?:ps\s*5|playstation\s*5)\b")
XBOX = re.compile(r"\bseries\s+([xs])\b")
ACCESSORIES = re.compile(
    r"\b(?:controller|kontroller|manette|gehäuse|cover|box|karton|kabel|netzteil|"
    r"mainboard|motherboard|alaplap)(?:s|n|e|ok)?\b"
)
CONSOLE = re.compile(r"\b(?:konsole|console)s?n?\b")
MULTIPLE = re.compile(r"\b(?:posten\s*\d+|lot|bundle of|\d+\s*(?:x|×)\s*(?:ps5|konsole|console))\b")
GENERATIONS = {"10": "Fat", "11": "Fat", "12": "Fat", "20": "Slim", "70": "Pro"}


def detect_model(title: str) -> str:
    title = title.casefold()
    if MULTIPLE.search(title):
        return BUNDLE
    if ACCESSORIES.search(title) and not CONSOLE.search(title):
        return ACCESSORY

    codes = CFI.findall(title)
    ps5 = bool(codes or PS5.search(title))
    xbox = set(XBOX.findall(title))
    if xbox:
        if ps5 or len(xbox) > 1:
            return UNKNOWN
        return f"Xbox Series {xbox.pop().upper()}"
    if not ps5:
        return UNKNOWN

    generations = {GENERATIONS[prefix] for prefix, _ in codes}
    if re.search(r"\bpro\b", title):
        generations.add("Pro")
    if re.search(r"\bslim\b", title):
        generations.add("Slim")
    if len(generations) > 1:
        return UNKNOWN

    generation = next(iter(generations), None)
    editions = {
        "Disc" if suffix == "a" else "Digital"
        for prefix, suffix in codes if GENERATIONS[prefix] == "Fat" and suffix
    }
    if re.search(r"\bdigital\b", title):
        editions.add("Digital")
    if re.search(r"\b(?:disc|disk)(?:\s+edition)?\b", title):
        editions.add("Disc")
    if len(editions) > 1:
        return UNKNOWN
    edition = next(iter(editions), None)
    if generation == "Fat":
        return f"PS5 (Fat) {edition}" if edition else "PS5 (Fat)"
    if generation is not None:
        return f"PS5 {generation}"
    return "PS5 Digital" if edition == "Digital" else UNKNOWN
