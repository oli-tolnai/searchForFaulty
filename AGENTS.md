# AGENTS.md – Console Deal Finder

Ez a fájl a kódoló agentnek (pl. Codex) szól. Minden munka előtt olvasd el.

## A projekt

Saját használatra készülő **Flutter-alkalmazás (Android és Windows)**, amely EU-s eBay-oldalakon hibás / alkatrésznek árult játékkonzolokat (PS5, Xbox Series X|S) keres, amelyek **közvetlenül Magyarországra rendelhetők**. A háttérrendszer **Google Apps Script** (a felhasználó privát Google-projektjében), az adattár **Google Sheets**, az értesítés az **app saját helyi értesítése** egy szerveroldali értesítési sorból (terv 19–20. pont); az ntfy későbbi, opcionális bővítés.

A `backend/` (Python/FastAPI) és a `frontend/` (React) mappa **referencia-prototípus**: a kimért logika portolásához használd, de ne fejleszd tovább, és ne töröld.

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

1. **Nincs demó- vagy kitalált adat az éles alkalmazásban.** Kitalált hirdetés, URL, ár, azonosító soha nem jelenhet meg a felületen. Rögzített mintaválaszok (fixture) **csak a tesztekben** használhatók (`apps_script/test/fixtures/`, `flutter_app/test/fixtures/`).
2. **Titkok helye:** az `EBAY_CLIENT_ID`, az `EBAY_CLIENT_SECRET`, a kliens-token(ek) (és az opcionális ntfy-adatok) **kizárólag az Apps Script Script Properties tárában** van. A Flutter-app csak a webapp címét és a kliens-tokent ismeri, és azokat `flutter_secure_storage`-ban tárolja (a felhasználó a Beállításokban adja meg). Titok soha nem kerülhet a kódba, a táblázatba, a naplóba, a Flutter buildbe vagy a gitbe. A `.clasp.json` (scriptId) és a webapp címe ne kerüljön a gitbe; a repóba csak minta (`.clasp.json.example`) kerül. A prototípus `.env` fájlja továbbra is csak helyben létezhet.
3. **A naplóban a tokenek és a kulcsok legyenek kitakarva.**
4. **Csak `ACTIVE` státuszú hirdetés jelenhet meg az aktív listában** (terv 17. pont). Bizonytalan esetben `UNKNOWN`, soha nem megalapozatlan `ACTIVE`.
5. **Ismeretlen adat = „Nem ismert”.** A szállítási díj soha ne legyen alapból 0. Hiányzó értéket ne pótolj becsléssel.
6. **Csak EU-tagállamban lévő termék** (`itemLocation.country` ellenőrzés az Apps Scriptben).
7. **Csak hivatalos API.** Scraping, bejelentkezés, CAPTCHA vagy hozzáférés-korlátozás megkerülése tilos. A Jófogás és a HardverApró csak előre kitöltött keresőlinkként szerepelhet.
8. **Ne használj fizetős szolgáltatást vagy AI API-t.**
9. **A teljes felhasználói felület magyar nyelvű.** A kód, a változónevek és a kommentek angolul legyenek.
10. **eBay-felhasználói személyes adatot tilos tárolni.** Az eladó felhasználóneve, értékelése, visszajelzési pontszáma és bármilyen vevői/eladói adat nem kerülhet a Sheetsbe, az Apps Script naplójába vagy gyorsítótárába, a kliens gyorsítótárába vagy az ntfy-értesítésbe, akkor sem, ha az API visszaadja. Nyers eBay-választ ne tárolj. Csak a hirdetés adatai tárolhatók (azonosító, cím, ár, szállítás, hely, kép URL, link, státusz, időpontok). Az eBay-kulcskészlet erre a feltételre kapott mentességet a *Marketplace Account Deletion* értesítések alól; ennek megszegése a kulcs letiltásához vezethet.

11. **A webapp minden kérését a titkos kliens-tokennel kell hitelesíteni**, a kérés legelején, még Sheets- vagy eBay-elérés előtt. Csak engedélyezett műveletek, méretkorláttal; hibás token vagy ismeretlen művelet → azonnali elutasítás, részletek nélkül.
12. **Frissesség:** megjelenített hirdetési adat legfeljebb 6 órás lehet (eBay License 8.1); a 2 óránál régebben ellenőrzött tétel `UNKNOWN` (terv 17.4).

## eBay Browse API – fontos részletek

- Hitelesítés: OAuth **client credentials** (application token), `POST https://api.ebay.com/identity/v1/oauth2/token`, scope: `https://api.ebay.com/oauth/api_scope`. A tokent cache-eld a lejáratáig.
- **Keresési stratégia (élesben mérve, 2026-11):**
  - Egyetlen marketplace: `X-EBAY-C-MARKETPLACE-ID: EBAY_DE`. Mérés szerint az `EBAY_DE` + `itemLocationCountry:FR` itemId-re pontosan ugyanazt adja, mint az `EBAY_FR` + `FR`, ezért más EU-s oldalt nem kell külön lekérdezni.
  - **Országonként és modellcsoportonként egy lekérdezés** `itemLocationCountry:<ország>` szűrővel, alapból mind a 27 EU-tagállamra (konfigurálható lista). Ha `total` > 200, lapozz (`offset`).
  - **Modellcsoportonként külön lekérdezés: `q=ps5` és `q=xbox series`** (országonként 2 hívás). A VAGY-szintaxist NE használd: mérve minden változata (`(ps5, playstation 5, xbox series)`, `(ps5,xbox)`, `(ps5,"xbox series")`) elveszíti a találatok nagy részét (73-ból 23–32 maradt), az egyszavas `xbox` pedig Xbox One/360/Classic tételeket hoz. A `q=playstation 5` ugyanazt adja, mint a `q=ps5`, ezért fölösleges. Kulcsszó nélkül sem működik (594 tételből 3 PS5).
  - A `q=ps5` más PlayStation-generációkat is visszaad (PS1, PS3, PSP stb.), ezért a háttérrendszer modellfelismerése kötelezően kiszűri a nem támogatott modelleket.
  - `X-EBAY-C-ENDUSERCTX`: a keresőben `contextualLocation=country%3DHU`. Mérve: a tételek kb. 70%-ánál az eBay 11510-es figyelmeztetéssel nem számol díjat, és ezen sem az irányítószám, sem a `getItem` nem segít. Ezeknél a díj „Nem ismert”; ne próbáld becsülni. Az irányítószámot (`HU_POSTAL_CODE`, csak diagnosztika) ne naplózd.
  - filter: `conditionIds:{7000}`, `deliveryCountry:HU`, `itemLocationCountry:<ország>`, `buyingOptions:{AUCTION|FIXED_PRICE}`
  - `category_ids=139971` (Video Game Consoles; Taxonomy API-val ellenőrizve)
- A `buyingOptions` szűrő minden keresésnél kötelező, mert nélküle az eBay kihagyja a kizárólag licitálható hirdetéseket. A fix áras, ajánlattételt is engedő hirdetések a `FIXED_PRICE` szűréssel érkeznek.
- **Az `itemLocationRegion` szűrőt NE használd.** `deliveryCountry:HU` mellett az eBay nem támogatja, és csak egy warningot ad (errorId 12519), a szűrőt figyelmen kívül hagyja; a találatok ilyenkor nagyrészt USA-beliek. A háttérrendszer saját EU-ellenőrzése (`itemLocation.country`) ettől függetlenül kötelező.
- A válasz `warnings` mezőjét mindig naplózd és jelezd: egy figyelmen kívül hagyott szűrő csendben hibás eredményt ad.
- **A `getItems` (kötegelt lekérés) ezzel a kulccsal NEM érhető el** (mérve: HTTP 400 `invalid_scope`, korlátozott hozzáférésű végpont). Státusz- és szállítási ellenőrzéshez tételenként `getItem` kell; az eredményt gyorsítótárazd, hogy ugyanazt a tételt ne kérd le újra feleslegesen.
- **Magyarországra szállítás ellenőrzése (mérve, 2026-11):** a `deliveryCountry:HU` szűrő ellenére az ismeretlen szállítási díjú tételek nagy része NEM szállít Magyarországra. A `getItem` válasz `shipToLocations` mezője ezt megmutatja: a 10 tételes mintából 9-nél `regionIncluded = [az eladó országa]` (csak belföldre szállít), 1-nél a `regionExcluded` kifejezetten tartalmazta a HU-t. Szabály:
  - **szállít HU-ra**, ha a `regionIncluded` tartalmazza a `HU`-t vagy egy HU-t magában foglaló régiót (pl. `WORLDWIDE`, `EUROPE`, `EUROPEAN_UNION`), és a `regionExcluded` nem zárja ki (sem `HU`, sem HU-t tartalmazó régió);
  - **nem szállít HU-ra**, ha a `regionExcluded` kizárja, vagy a `regionIncluded` nem üres, de sem a `HU`-t, sem HU-t tartalmazó régiót nem tartalmaz (pl. csak `["DE"]`);
  - **nem eldönthető**, ha a mező hiányzik vagy üres, vagy a lekérés sikertelen.
- **Hívásszám-keret:** a napi keret 5000 Browse-hívás (mérve). A konzolkeresés 54, a kontrollerkeresés 108 első oldalt kér le, együtt 162-t. A lapozásra és újrapróbálásra külön, korlátozott tartalék van. A szállítási próba legfeljebb 100 `getItem`-hívást indít keresésenként. Számold a napi hívásokat.
- Ha egy API-mező vagy funkció nem úgy működik, ahogy a terv feltételezi, ne kerüld meg csendben: írd le az összefoglalóban.
- Hivatalos dokumentáció: https://developer.ebay.com/api-docs/buy/browse/overview.html

## Technológia és mappaszerkezet

```
apps_script/        Google Apps Script (V8 JavaScript) háttérrendszer
  src/              a feltöltendő kód (clasp rootDir); üzleti logika tiszta függvényekben
  test/             Node.js tesztek (node:test), mockolt UrlFetchApp / SpreadsheetApp / PropertiesService / CacheService
    fixtures/       rögzített eBay-mintaválaszok (csak teszthez)
  appsscript.json   manifeszt (időzóna: Europe/Budapest, V8, webapp beállítások)
  .clasp.json.example
  package.json      csak fejlesztői eszközök (tesztfuttatás, clasp)
flutter_app/        Flutter-kliens (Android, Windows)
backend/, frontend/ referencia-prototípus (nem fejlesztjük)
spikes/             egyszeri mérések
docs/               vizsgálatok, jelentések
```

**Apps Script-szabályok:**
- A `src/` kód a Google V8 futtatókörnyezetben fut, nem Node.js-ben: Node- és böngésző-API-t (require, fs, fetch, setTimeout, Buffer) ne használj; ES-modul import/export helyett globális függvények / objektumok. A tesztek a `src/` fájlokat Node.js `vm` modullal vagy hasonló módon töltsék be.
- eBay-hívás `UrlFetchApp.fetch` / `fetchAll` (`muteHttpExceptions: true`), párhuzamosan kötegekben. Mérve a telepített webappon át: 4-es kötegekkel a teljes keresés 15 mp, 8-as kötegekkel 9,2 mp, 0 hiba – a `FETCH_BATCH_SIZE` ajánlott értéke 8.
- eBay-token a `CacheService`-ben, lejáratig. Hívásszámláló a Script Properties-ben, napi bontásban.
- Sheets-írás `LockService.getScriptLock()` alatt, kötegelten (`setValues`), hálózati hívás zár alatt nem futhat. A szöveges cellák elé képletinjekció ellen védelem (pl. a `=`, `+`, `-`, `@` kezdetű értékek szövegként tárolása).
- Webapp: `doPost(e)`, JSON be és ki, a válaszban alkalmazásszintű `ok` / `error.code` (HTTP-státusz nem állítható).

**Flutter-szabályok:**
- Az Apps Script webapp `/exec` POST-ja 302/303-mal átirányít a `script.googleusercontent.com`-ra: az első kérésnél az automatikus átirányítás legyen kikapcsolva, és a `Location` címre (csak a várt hostra) GET menjen, az eredeti törzs és token nélkül. HTML vagy bejelentkezési oldal válasz = hiba.
- A kliens a válasz JSON-t sémához validálja; hiányzó mező nem pótolható kitalált értékkel.
- Linkek (eBay-hirdetés, Google Fordító) a rendszer böngészőjében nyíljanak.

Új függőséget csak akkor vegyél fel, ha valóban szükséges, és írd bele az összefoglalóba.

## Parancsok

Amíg nincsenek létrehozva, az első érintett feladatban hozd létre őket, és itt frissítsd a listát.

```powershell
# Apps Script (a repó gyökeréből)
cd apps_script
npm ci
npm test
npm run lint
npx clasp login        # egyszer, a felhasználó Google-fiókjával
npx clasp create --type standalone --title "Console Deal Finder" --rootDir src  # ha még nincs projekt
Copy-Item -LiteralPath appsscript.json -Destination src/appsscript.json -Force
npx clasp push --force # a src/ és a manifest feltöltése a kiválasztott projektbe
node tools/measure_webapp.mjs  # CDF_WEBAPP_URL és CDF_TOKEN szükséges
```

A Google-fiók, a meglévő projekt csatlakoztatása, a Script Properties és a telepítés lépései az [Apps Script útmutatójában](apps_script/README.md) szerepelnek.

```powershell
# Flutter (a repó gyökeréből)
cd flutter_app
flutter pub get
flutter test
flutter analyze
flutter run -d windows
flutter build windows
flutter build apk --release
```

A prototípus parancsai (csak referencia, összehasonlításhoz): `backend/` → `.\.venv\Scripts\pytest.exe`, `.\.venv\Scripts\python.exe -m uvicorn app.main:app`; `frontend/` → `npm ci`, `npm run dev`.

## Tesztek

- Kötelező tesztek: szűrés (ár, modell, EU-hely), deduplikáció, árkalkuláció (ismeretlen szállítással is), státuszkezelés (terv 17.6), modellfelismerés, webapp-hitelesítés, eladói adat eldobása.
- A prototípus `backend/tests` modellfelismerési és szűrési tesztesetei mind kerüljenek át az Apps Script-tesztekbe, azonos elvárt eredménnyel.
- A tesztek nem hívhatják az éles eBay API-t; HTTP-mockkal és fixture-ökkel dolgozz.
- Tesztet kikapcsolni, átugrani vagy gyengíteni azért, hogy átmenjen, tilos.

## Git

- Commit előtt: tesztek és linter zöldek.
- Soha ne commitold: `.env`, `*.db`, `.venv/`, `node_modules/`, `.clasp.json`, `.clasprc.json`, build-kimenet (`flutter_app/build/`), `.apk`.
