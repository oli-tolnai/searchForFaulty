# Console Deal Finder

Az első fejlesztési feladat eredménye egy minimális FastAPI-backend és egy
parancssori eBay-kulcsellenőrző. A backend egyetlen végpontja a `GET /api/health`.

## Telepítés Windowson

Windowsra a Python 3.14 ajánlott, a legkisebb támogatott verzió a 3.12.
A Python telepítéskezelőjével (`pymanager`), a repó
gyökeréből, PowerShellben futtasd:

```powershell
cd backend
pymanager exec -V:3.14 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## eBay-kulcsok beállítása és ellenőrzése

1. Jelentkezz be az [eBay Developers Program](https://developer.ebay.com/)
   oldalán, és az **Application Keys** részen válaszd a **Production**
   kulcskészletet. Az éles kulcshoz teljesíteni kell a Marketplace Account
   Deletion követelményt. Ehhez a projekthez a fejlesztői portálon mentesség
   kérhető, mivel a szkript nem tárol eBay-felhasználói adatot.
2. A repó gyökerében másold a `.env.example` fájlt `.env` néven, és töltsd ki:
   `EBAY_CLIENT_ID` = **App ID**, `EBAY_CLIENT_SECRET` = **Cert ID**.
   A Dev ID nem szükséges. Az üresen hagyott `EBAY_ENV` értéke `production`;
   a `sandbox` beállítással a szkript csak a tesztkörnyezet tokenjét ellenőrzi.
   A `.env` fájlt ne commitold.
3. A `backend` mappában futtasd:

   ```powershell
   .\.venv\Scripts\python.exe -m scripts.check_ebay
   ```

A szkript kiírja a token lejáratát, a napi Browse-keretet és a hátralévő
hívásokat, ha az Analytics API megadja ezeket, majd a Taxonomy API-ból
ellenőrzött konzolkategóriával német eBay-próbakeresést futtat. Legfeljebb
tíz tételt mutat, és jelzi a nem EU-s vagy ismeretlen termékhelyet. A token
értéke és az eladói adatok nem kerülnek a kimenetbe. A szkript nem ment
hirdetéseket vagy válaszokat fájlba, illetve adatbázisba.

A `buyingOptions:{AUCTION|FIXED_PRICE}` szűrővel a próbakeresés aukciókat és
fix áras hirdetéseket is kér. Minden tételnél megjelennek az eBay által
visszaadott hirdetéstípusok, köztük az ajánlattétel, ha elérhető.
A hiányzó vagy számított szállítási díj „Nem ismert”.
A sikeres tokenkérés önmagában még nem igazolja a Browse-hozzáférést.
Az eBay-adatok használatára az [API License Agreement](https://developer.ebay.com/develop/api-license-agreement)
vonatkozik.

Az eBay helyszűrőinek éles összevetéséhez a `backend` mappából futtasd a
`python -m scripts.compare_location_filters` parancsot az aktivált virtuális
környezetben. A szkript változatonként egy, legfeljebb 200 tételes oldalt
vizsgál. Az országeloszlást és az egyedi EU-s tételek számát a visszakapott
oldalakból számolja, az API által közölt teljes találatszámot külön mutatja.

A `python -m scripts.compare_country_strategy` parancs ugyaninnen futtatható.
A piacterek és a kulcsszó hatását vizsgálja. Lekérdezésenként legfeljebb három,
egyenként 200 tételes oldalt kér, és a lekért oldalak egyedi hirdetéseit veti össze.

A `python -m scripts.diagnose_search_quality --shipping-only` ugyanazon a
mintán hasonlítja össze a szállítási fejléceket. A harmadik változathoz
opcionálisan megadható a `HU_POSTAL_CODE` a gyökérszintű `.env` fájlban.

## Keresési API

Az elindított backend `POST /api/search` végpontja üres JSON-objektummal
az összes beállított országban keres. Opcionális szűrők a `max_price`,
`max_total_price`, `buying_options` (`auction`, `fixed` vagy `both`) és
`console_models` (modellnevek listája). Az `include_mainboards` bekapcsolja
az alaplapokat. Az `item_type_counts` az aktív, EU-s, deduplikált tételeket
számolja a válasz szűrőinek alkalmazása előtt. Az ismeretlen szállítási díjú
találatok az `unknown_shipping` listába kerülnek. A válaszban
`partial` jelzi a részleges országkudarcot. Ha minden ország hibát ad,
a végpont HTTP 502 választ küld az országonkénti hibákkal.

A gyökérszintű `.env` fájlban az `EBAY_SEARCH_QUERIES` az eBay kulcsszavait JSON-listaként,
az `EBAY_COUNTRIES` pedig az országok JSON-listáját állítja be
(például `EBAY_COUNTRIES='["DE","FR"]'`). Az alapértelmezés
`["ps5","xbox series"]` és mind a 27 EU-tagállam. A backend a mért,
URL-kódolt, irányítószám nélküli fejlécet használja.
A két árkorlát a tétel pénznemében értendő. A teljes árhoz az árnak és a
szállításnak azonos pénznemben kell szerepelnie. A napi hívásszámláló a
backend folyamatának memóriájában, UTC szerinti napokra bontva működik.

## Tesztelés és helyi indítás

A `backend` mappában:

```powershell
.\.venv\Scripts\pytest.exe
.\.venv\Scripts\ruff.exe check .
.\.venv\Scripts\python.exe -m uvicorn app.main:app
```

A tesztek HTTP-mockokat használnak, így eBay-kulcs és internetkapcsolat nélkül
futtathatók. Az elindított backend a
[`http://127.0.0.1:8000/api/health`](http://127.0.0.1:8000/api/health) címen
`{"status":"ok"}` választ ad. Ehhez sem kell eBay-kulcs.
