import re
from dataclasses import dataclass

from app.models import ItemType

UNKNOWN = "Ellenőrzendő"
PS5_UNSPECIFIED = "PS5 (változat nem ismert)"

CFI = re.compile(r"\bcfi[-\s]?(10|11|12|20|70)\d{2}([ab])?\b")
PS5 = re.compile(r"\b(?:ps\s*5|play\s*station\s*5)\b")
XBOX = re.compile(r"\bseries\s+([xs])\b")
XBOX_MIXED = re.compile(r"\bseries\s+[xs]\s*[/|]\s*[xs]\b")
UNSUPPORTED = {
    "PS1": r"\b(?:ps\s*1|psx|ps\s*one|playstation\s*(?:1|one))\b",
    "PS2": r"\b(?:ps\s*2|playstation\s*2)\b",
    "PS3": r"\b(?:ps\s*3|playstation\s*3|cech[-\s]?[a-z0-9]+)\b",
    "PS4": r"\b(?:ps\s*4|playstation\s*4|cuh[-\s]?\d{4}[a-z]?)\b",
    "PSP": r"\b(?:psp|playstation\s+portable)\b",
    "PS Vita": r"\b(?:ps|playstation)\s*vita\b",
    "Xbox One": r"\bxbox\s+one\b",
    "Xbox 360": r"\bxbox\s+360\b",
    "Xbox Classic": (
        r"\b(?:xbox\s+(?:classic|original)|(?:classic|original)\s+xbox|"
        r"xbox\s+(?:konsole\s+)?erste\s+serie)\b"
    ),
    "Nintendo Switch": r"\b(?:nintendo\s+switch|switch(?:\s+(?:lite|oled|2))?)\b",
    "Nintendo Wii": r"\b(?:nintendo\s+)?wii(?:\s+u)?\b",
    "Nintendo DS": r"\b(?:nintendo\s+ds|(?:2ds|3ds))\b",
}
CONSOLE_WORD = re.compile(r"\b(?:spielkonsole|wohnkonsole|heimkonsole|konsole|console)s?n?\b")
CONSOLE_FEATURE = re.compile(
    r"\b(?:825\s*gb|[12]\s*tb|(?:disc|disk|digital)(?:e)?\s+edition|"
    r"für\s+teile|for\s+parts|nicht\s+funktionsfähig|läuft\s+nicht|"
    r"bundle\s+(?:inkl\.?|including|mit|with))\b"
)
BOARD = re.compile(r"\b(?:mainboards?|motherboards?|alaplap|edm[-\s]?0\d{2})\b")
EXPLICIT_CONSOLE = re.compile(
    r"\b(?:nur\s+konsole|console\s+only|komplette?\s+(?:ps5\s+)?konsole|"
    r"complete\s+(?:ps5\s+)?console|(?:konsole|console)\s+(?:mit|with))\b"
)
EMPTY_BOX = re.compile(
    r"\b(?:box|ovp|karton)\b.*\b(?:leer|empty|nur)\b|"
    r"\b(?:leer\w*|empty|nur|only)\s+(?:box|ovp|karton)\b"
)
PARTS = re.compile(
    r"\b(?:controller|kontroller|dualsense|manette|gehäuse|cover|box|ovp|karton|kabel|"
    r"netzteil|lüfter|hdmi[-\s]+(?:port|buchse))(?:s|n|e|ok)?\b"
)
SERVICE = re.compile(
    r"\b(?:liquid\s+metal|wärmeleitpaste|reinigung|reparaturservice|reparatur[-\s]+service|"
    r"service|repair\s+service|reparatur)\b"
)
ONLY_PART = re.compile(
    r"\b(?:nur|only)\s+(?:controller|kontroller|dualsense|manette|lüfter|netzteil|"
    r"cover|gehäuse|hdmi[-\s]+(?:port|buchse))\b"
)
MULTIPLE = re.compile(
    r"\b(?:posten\s*\d+|lot|bundle of|[2-9]\d*\s*(?:x|×)\s*(?:ps5|xbox|konsole|console))\b"
)
BANNED = re.compile(r"\b(?:banned|gebannt|gesperrt)\b")
GENERATIONS = {"10": "Fat", "11": "Fat", "12": "Fat", "20": "Slim", "70": "Pro"}


@dataclass(frozen=True)
class Classification:
    item_type: ItemType
    console_model: str
    is_banned: bool
    reason: str | None = None


def classify_item(title: str) -> Classification:
    title = title.casefold()
    banned = bool(BANNED.search(title))
    codes = CFI.findall(title)
    ps5 = bool(codes or PS5.search(title))
    xbox = set(XBOX.findall(title))
    unsupported = [model for model, pattern in UNSUPPORTED.items() if re.search(pattern, title)]
    console_word = CONSOLE_WORD.search(title)
    console_feature = CONSOLE_FEATURE.search(title)
    explicit_console = EXPLICIT_CONSOLE.search(title)
    generations = {GENERATIONS[prefix] for prefix, _ in codes}
    if ps5:
        if re.search(r"\bpro\b", title):
            generations.add("Pro")
        if re.search(r"\bslim\b", title):
            generations.add("Slim")
    editions = {
        "Disc" if suffix == "a" else "Digital"
        for prefix, suffix in codes if GENERATIONS[prefix] == "Fat" and suffix
    }
    if re.search(r"\bdigital(?:e)?\b", title):
        editions.add("Digital")
    if re.search(r"\b(?:disc|disk)\b", title):
        editions.add("Disc")

    conflicts = (
        len(xbox) > 1 or bool(XBOX_MIXED.search(title)) or len(generations) > 1
        or (bool(ps5 or xbox) and len(editions) > 1)
        or (ps5 and bool(xbox)) or ((ps5 or xbox) and bool(unsupported))
    )
    model = UNKNOWN
    if not conflicts:
        if ps5:
            generation = next(iter(generations), None)
            model = {"Fat": "PS5 (Fat)", "Slim": "PS5 Slim", "Pro": "PS5 Pro"}.get(
                generation, PS5_UNSPECIFIED
            )
            if editions:
                model += f" {next(iter(editions))}"
        elif xbox:
            model = f"Xbox Series {next(iter(xbox)).upper()}"
            if len(editions) == 1:
                model += f" {next(iter(editions))}"
        elif len(unsupported) == 1:
            model = unsupported[0]

    def result(item_type: ItemType, reason: str | None = None) -> Classification:
        return Classification(item_type, model, banned, reason)

    part = PARTS.search(title)
    service = SERVICE.search(title)
    if EMPTY_BOX.search(title) or ONLY_PART.search(title):
        return result("not_console", "A cím üres dobozt vagy önálló kiegészítőt jelöl.")
    if BOARD.search(title) and not explicit_console:
        return result("mainboard", "A cím alaplapot jelöl.")
    if service and not explicit_console:
        return result("not_console", f"A cím szolgáltatásra vagy anyagra utal: „{service.group()}”.")
    strong_console = bool(console_word or console_feature or codes or xbox or (ps5 and banned))
    if part and not strong_console:
        return result("not_console", f"A cím önálló kiegészítőre utal: „{part.group()}”.")
    if conflicts:
        return result("needs_review", "A címben ellentmondó modell- vagy kiadásjelölések vannak.")
    if unsupported:
        return result("unsupported_model", "A cím nem támogatott konzolmodellt jelöl.")
    if MULTIPLE.search(title) and (ps5 or xbox or strong_console):
        return result("console_bundle")
    if (strong_console or generations) and (ps5 or xbox):
        return result("console")
    return result("needs_review", "A cím alapján nem egyértelmű, hogy támogatott teljes konzolról van szó.")
