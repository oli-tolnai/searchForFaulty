# Console Deal Finder

Az első fejlesztési feladat eredménye egy minimális FastAPI-backend és egy
parancssori eBay-kulcsellenőrző. A backend egyetlen végpontja a `GET /api/health`.

## Telepítés Windowson

Telepítsd a Python 3.12-t a Windows Python-indítóval (`py`). A repó
gyökeréből, PowerShellben futtasd:

```powershell
cd backend
py -3.12 -m venv .venv
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
