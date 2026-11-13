# AGENTS.md – Console Deal Finder

Ez a fájl a kódoló agentnek (pl. Codex) szól. Minden munka előtt olvasd el.

## A projekt

Saját használatra készülő webalkalmazás, amely EU-s eBay-oldalakon hibás / alkatrésznek árult játékkonzolokat (PS5, Xbox Series X|S) keres, amelyek **közvetlenül Magyarországra rendelhetők**.

**Az egyetlen hiteles specifikáció: [`console_deal_finder_terv.md`](console_deal_finder_terv.md).** Ha egy utasítás ellentmond a tervnek, állj meg, és kérdezz. Ne találd ki a választ.

## Munkamódszer

- **Csak azt a feladatot csináld meg, amit az aktuális utasítás kér.** Ne kezdj bele a következő fázisba, és ne építs „előre” funkciókat.
- A terv fázisai (14. pont) sorrendben készülnek. Az aktuális fázist mindig az utasítás mondja meg.
- Minden feladat végén:
  1. futtasd le a teszteket és a lintert (parancsok lent),
  2. indítsd el az alkalmazást, ha a feladat érinti,
  3. írj rövid összefoglalót: mi készült el, mi **nem** készült el, mit nem tudtál ellenőrizni, és miért.
- Ha valamit nem tudsz valós adattal ellenőrizni (pl. nincs API-kulcs), ezt mondd ki egyértelműen. Ne állítsd, hogy működik.
- Kis, áttekinthető commitok, angol nyelvű commit-üzenetekkel.

## Megszeghetetlen szabályok

1. **Nincs demó- vagy kitalált adat az éles alkalmazásban.** Kitalált hirdetés, URL, ár, azonosító soha nem jelenhet meg a felületen. Rögzített mintaválaszok (fixture) **csak a tesztekben** használhatók, a `backend/tests/fixtures/` mappában.
2. **Titkok csak a `.env` fájlban.** Az `EBAY_CLIENT_ID` és az `EBAY_CLIENT_SECRET` soha nem kerülhet a kódba, a frontendbe, a naplóba vagy a gitbe. A `.env` legyen a `.gitignore`-ban; a repóba csak a `.env.example` kerül, üres értékekkel.
3. **A naplóban a tokenek és a kulcsok legyenek kitakarva.**
4. **Csak `ACTIVE` státuszú hirdetés jelenhet meg az aktív listában** (terv 17. pont). Bizonytalan esetben `UNKNOWN`, soha nem megalapozatlan `ACTIVE`.
5. **Ismeretlen adat = „Nem ismert”.** A szállítási díj soha ne legyen alapból 0. Hiányzó értéket ne pótolj becsléssel.
6. **Csak EU-tagállamban lévő termék** (`itemLocation.country` ellenőrzés a backendben, a régiószűrő mellett is).
7. **Csak hivatalos API.** Scraping, bejelentkezés, CAPTCHA vagy hozzáférés-korlátozás megkerülése tilos. A Jófogás és a HardverApró csak előre kitöltött keresőlinkként szerepelhet.
8. **Ne használj fizetős szolgáltatást vagy AI API-t.**
9. **A teljes felhasználói felület magyar nyelvű.** A kód, a változónevek és a kommentek angolul legyenek.
10. **eBay-felhasználói személyes adatot tilos tárolni.** Az eladó felhasználóneve, értékelése, visszajelzési pontszáma és bármilyen vevői/eladói adat nem kerülhet az adatbázisba, a naplóba vagy a cache-be, akkor sem, ha az API visszaadja. Csak a hirdetés adatai tárolhatók (azonosító, cím, ár, szállítás, hely, kép URL, link, státusz, időpontok). Az eBay-kulcskészlet erre a feltételre kapott mentességet a *Marketplace Account Deletion* értesítések alól; ennek megszegése a kulcs letiltásához vezethet.

## eBay Browse API – fontos részletek

- Hitelesítés: OAuth **client credentials** (application token), `POST https://api.ebay.com/identity/v1/oauth2/token`, scope: `https://api.ebay.com/oauth/api_scope`. A tokent cache-eld a lejáratáig.
- Minden kereséshez:
  - `X-EBAY-C-MARKETPLACE-ID`: a bekapcsolt EU-s oldal (`EBAY_DE`, `EBAY_AT`, `EBAY_FR`, `EBAY_IT`, …)
  - `X-EBAY-C-ENDUSERCTX: contextualLocation=country=HU`
  - filter: `conditionIds:{7000}`, `deliveryCountry:HU`, `itemLocationRegion:EUROPEAN_UNION`, `buyingOptions:{…}`
  - kategória: Video Game Consoles (az azonosítót a Taxonomy API-val ellenőrizd, ne feltételezd)
- Az `itemLocationRegion` és az `itemLocationCountry` nem használható együtt.
- Státuszellenőrzés: `getItems` (max. 20 tétel/hívás).
- **Hívásszám-keret:** egy teljes keresés az alapbeállításokkal maradjon 50 hívás alatt. Számold a napi hívásokat.
- Ha egy API-mező vagy funkció nem úgy működik, ahogy a terv feltételezi, ne kerüld meg csendben: írd le az összefoglalóban.
- Hivatalos dokumentáció: https://developer.ebay.com/api-docs/buy/browse/overview.html

## Technológia és mappaszerkezet

```
backend/            Python 3.12, FastAPI, HTTPX, SQLite
  app/
    adapters/       forrásonkénti adapterek (ebay.py, …), közös interfész
    services/       keresés, deduplikáció, státusz, árfolyam
    db/             séma, migrációk, lekérdezések
    api/            FastAPI-útvonalak
  tests/
    fixtures/       rögzített eBay-mintaválaszok (csak teszthez)
  scripts/          egyszeri segédszkriptek (pl. kulcsellenőrzés, oldalmérés)
frontend/           React + TypeScript + Vite + Tailwind CSS
.env.example
README.md
```

Új függőséget csak akkor vegyél fel, ha valóban szükséges, és írd bele az összefoglalóba.

## Parancsok

Amíg nincsenek létrehozva, az első érintett feladatban hozd létre őket, és itt frissítsd a listát.

```powershell
# Backend (Windows PowerShell, a repó gyökeréből)
cd backend
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\pytest.exe
.\.venv\Scripts\ruff.exe check .
.\.venv\Scripts\python.exe -m scripts.check_ebay  # Kitöltött gyökérszintű .env szükséges
.\.venv\Scripts\python.exe -m uvicorn app.main:app
```

```bash
# Frontend (még nem létezik)
cd frontend
npm install
npm run dev
npm run build
npm run lint
```

## Tesztek

- Kötelező tesztek: szűrés (ár, modell, EU-hely), deduplikáció, árkalkuláció (ismeretlen szállítással is), státuszkezelés (terv 17.6), modellfelismerés.
- A tesztek nem hívhatják az éles eBay API-t; HTTP-mockkal és fixture-ökkel dolgozz.
- Tesztet kikapcsolni, átugrani vagy gyengíteni azért, hogy átmenjen, tilos.

## Git

- Commit előtt: tesztek és linter zöldek.
- Soha ne commitold: `.env`, `*.db`, `.venv/`, `node_modules/`, build-kimenet.
