# Console Deal Finder · Apps Script

Az Apps Script webapp az eBay-keresést és a hirdetésrészletek lekérését végzi. A konfigurációt, valamint a budapesti naptári nap szerinti eBay-hívásszámlálót a Script Properties tárolja.

## 1. Helyi előkészítés Windowson

Telepíts egy támogatott Node.js LTS-verziót (legalább Node.js 20). A repó gyökeréből, PowerShellben futtasd a következőket.

```powershell
cd apps_script
npm ci
npm test
npm run lint
```

A Google-fiókoddal kapcsold be az **Apps Script API** beállítást, majd jelentkezz be a `clasp` eszközzel ugyanebbe a fiókba. [Apps Script-felhasználói beállítások](https://script.google.com/home/usersettings)

```powershell
npx clasp login
```

## 2. A Google-projekt kiválasztása és feltöltése

Új, önálló projekthez futtasd a következő parancsot. A `clasp` létrehozza a helyi `.clasp.json`-t, és letöltheti a Google üres kezdőfájljait a `src/` mappába. Ha létrejött a mintaként generált `src/Code.js`, töröld.

```powershell
npx clasp create --type standalone --title "Console Deal Finder" --rootDir src
```

Meglévő projekt esetén először mentsd annak kódját. Egy külön, üres mappában a `npx --package=@google/clasp@3.2.0 clasp clone <Script-ID>` letölti a meglévő fájlokat. A repó `apps_script/` mappájában másold a `.clasp.json.example` fájlt `.clasp.json`-ra, és töltsd ki a `scriptId`-t a Google-projekt **Project Settings → Script ID** mezőjével. A `rootDir` értéke `src`.

A `clasp push` lecseréli a kiválasztott Google-projekt aktuális forrását. Minden feltöltés előtt másold a verziózott manifestet oda, ahol a `clasp` keresi.

```powershell
Copy-Item -LiteralPath appsscript.json -Destination src/appsscript.json -Force
npx clasp push --force
```

## 3. Script Properties

Az Apps Script szerkesztőben nyisd meg a **Project Settings → Script Properties** részt. Add meg az alábbi értékeket.

| Név | Érték |
|---|---|
| `EBAY_CLIENT_ID` | Az éles eBay App ID |
| `EBAY_CLIENT_SECRET` | Az éles eBay Cert ID |
| `CLIENT_TOKENS` | Legalább 256 bites véletlen kliens-token. Cserénél ideiglenesen vesszővel elválasztva a régi és az új érték is megadható. |
| `FETCH_BATCH_SIZE` | Opcionális. Az alapérték `4`. |

Az alábbi PowerShell-kód 32 bájt kriptográfiailag biztonságos véletlenből base64url tokent képez, és a vágólapra teszi. Illeszd be a Google felületén a `CLIENT_TOKENS` értékeként. A `$cdfToken` ugyanabban a PowerShell-ablakban a méréshez is használható. A beillesztés után ürítheted a vágólapot a `Set-Clipboard -Value ''` paranccsal.

```powershell
$cdfBytes = New-Object byte[] 32
$cdfRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $cdfRng.GetBytes($cdfBytes) } finally { $cdfRng.Dispose() }
$cdfToken = [Convert]::ToBase64String($cdfBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
Set-Clipboard -Value $cdfToken
```

## 4. Webapp telepítése

1. A szerkesztőben válaszd a **Deploy → New deployment → Web app** lehetőséget.
2. Az **Execute as** legyen **Me**, a **Who has access** pedig **Anyone**, hogy a Flutter később Google-bejelentkezés nélkül elérhesse. Az API a JSON-törzs kliens-tokenjét ellenőrzi.
3. Kattints a **Deploy** gombra, és kérés esetén engedélyezd a külső kéréseket. Másold ki a **Web app URL** mezőből a `/exec` végű címet.
4. Későbbi feltöltés után a meglévő címet a **Deploy → Manage deployments → Edit → New version** útvonalon frissítheted.

A forrás feltöltése és a webapp-verzió telepítése külön művelet. [Google webapp-útmutató](https://developers.google.com/apps-script/guides/web) · [Verziózott telepítések](https://developers.google.com/apps-script/concepts/deployments)

## 5. Éles mérés

Az `apps_script/` mappában állítsd be a két környezeti változót a futtatás idejére. Ha a `$cdfToken` már nincs az aktuális PowerShell-munkamenetben, a második sor helyett használd a `$env:CDF_TOKEN = Read-Host 'Kliens-token' -MaskInput` parancsot PowerShell 7-ben. Windows PowerShell 5.1-ben használhatod a `$env:CDF_TOKEN = Get-Clipboard` parancsot közvetlenül a token biztonságos kimásolása után.

```powershell
$env:CDF_WEBAPP_URL = Read-Host 'A telepített webapp /exec címe'
$env:CDF_TOKEN = $cdfToken
try {
  node tools/measure_webapp.mjs
} finally {
  Remove-Item Env:CDF_WEBAPP_URL, Env:CDF_TOKEN
  Remove-Variable cdfToken, cdfBytes, cdfRng -ErrorAction SilentlyContinue
}
```

A mérő kiírja az első és öt további ping idejét, a teljes keresés idejét, találatait, eBay-hívásait és a hibás token ellenőrzését. Az első ping mutathatja a hidegindítást, ha a Google éppen új futtatókörnyezetet indított. A méréshez csak az összesítő sorokat küldd vissza. A webapp-cím, kliens-token és eBay-kulcs maradjon a saját gépeden.

Sikertelen vagy részleges keresésnél a mérő megmutatja a lekérdezéshibákat és az előfordulásuk számát. Ha a webapp hibaválaszt ad, a mérő kiírja a hibakódot.

## eBay-token diagnosztikája

1. Nyisd meg a **Console Deal Finder** projekt **Szerkesztő** nézetét. Ha a feltöltés óta nyitva van, frissítsd az oldalt.
2. A fájllistában válaszd az **ebay.gs** fájlt, majd a felső függvénylistában a **diagnoseEbayToken** függvényt. Kattints a **Futtatás** gombra.
3. Ha a Google engedélyt kér a külső kérésekhez, add meg az engedélyt a projekt tulajdonosaként. Ezután ellenőrizd a **Végrehajtási napló** panelt. Ha a függvény még nem futott le, indítsd el újra.

A diagnosztika egy friss OAuth-kérést indít. A naplóban például `HTTP 200`, `HTTP 401 | error: invalid_client` vagy a kitakart Apps Script-kivétel jelenik meg. A függvényhez elég a forrás feltöltése. A `/exec` címen futó verziót a **Bevezetés → Bevezetések kezelése** alatt lehet frissíteni. [Google útmutató az Apps Script engedélyhibáihoz](https://developers.google.com/apps-script/guides/support/troubleshooting)

## A kliensnek szánt API

A `POST` JSON-törzse `token`, `action`, `params` és opcionális `request_id` mezőből áll. A felső mérethatár 10 240 bájt. Az egyszerű, legfeljebb 128 karakteres kérésazonosítót a válasz visszaadja. A `doGet` csak az API nevét adja vissza.

| `action` | `params` | `data` |
|---|---|---|
| `ping` | `{}` | `version`, `server_time` |
| `search` | Opcionális `countries` ISO-kódokkal és `queries` a `ps5`, `xbox series` értékek közül. Mindkettő alapértéke a teljes lista. | Normalizált tételek, `unknown_shipping`, típus- és szállítási bontás, országonkénti és lekérdezésenkénti állapot, számlálók. Az alaplapokat is lekéri a későbbi kliensoldali szűréshez. |
| `listing_details` | `source_listing_id` az eBay Browse válaszából | `condition_description`, `short_description`, `description_text` vagy `null` a hiányzó mezőknél. Egyszerű szövegként jelenítsd meg. |

A `search` esetében az `ok: true` azt jelenti, hogy a keresés állapota kiolvasható a `data` mezőből. A kliens ott ellenőrizze a `status` értékét. A `partial` a keresés hiányosságát, az `error` minden első oldal sikertelenségét jelzi. A pénzösszegek decimális sztringek. A napi számláló a projekten keresztül megkísérelt eBay-hívásokat számolja, budapesti idő szerint.

A Content Service a válaszhoz külön Google URL-t ad. A kliens a POST átirányítását kézzel kezelje, majd a `script.googleusercontent.com` címet GET-tel, az eredeti törzs és token nélkül nyissa meg. [Content Service átirányítás](https://developers.google.com/apps-script/guides/content#redirects)
