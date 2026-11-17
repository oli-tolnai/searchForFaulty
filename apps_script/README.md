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

### A Sheets-szinkron engedélyezése

1. A friss forrás feltöltése után nyisd meg a szerkesztőben a **state.gs** fájlt, válaszd az **initializeState** függvényt, majd kattints a **Futtatás** gombra.
2. Engedélyezd a Google Táblázatok elérését a projekt tulajdonosaként. Ha szükséges, futtasd újra a függvényt. A naplóban **A szinkrontáblázat készen áll.** jelenik meg. A projekt első használatkor létrehozza a **Console Deal Finder – adatok** táblázatot, ha még nincs `SHEET_ID` beállítva.
3. A meglévő webappnál válaszd a **Bevezetés → Bevezetések kezelése → Szerkesztés → Új verzió → Bevezetés** útvonalat. Az eddigi `/exec` cím és kliens-token használható tovább.

A Google Táblázatok engedélye az alkalmazás által létrehozott vagy a `SHEET_ID`-ben megadott fájl megnyitásához szükséges. [SpreadsheetApp dokumentáció](https://developers.google.com/apps-script/reference/spreadsheet/spreadsheet-app)

### Értesítések bekapcsolása

1. Ha az időzítők még nincsenek telepítve, futtasd a szerkesztőben a **notifications.gs** fájlból az **installTriggers** függvényt, és engedélyezd az időzítők kezelését.
2. A meglévő webappnál válaszd a **Bevezetés → Bevezetések kezelése → Szerkesztés → Új verzió → Bevezetés** útvonalat. Telepítsd az új Android- vagy Windows-verziót, amely a meglévő `/exec` címmel és kliens-tokennel használható.
3. Az alkalmazás Beállítások lapján válaszd a **Próbaértesítés** gombot. A **notifications** munkalap az első kéréskor létrejön. Androidon engedélyezd a rendszerértesítéseket is.

Az aukciófigyelés 10 percenként, az új találatok ellenőrzése 2 óránként fut. A **removeTriggers** függvénnyel mindkettő kikapcsolható. Az értesítéseket az appok eszközönként nyugtázzák. Az aukciós jelzés a záráskor, a találati összefoglaló legfeljebb hat óra múlva, a próbaüzenet 24 óra múlva jár le. A korábbi ntfy-csatorna inaktív, amíg az `NTFY_ENABLED` nincs `true` értékre állítva. [Apps Script időzítők](https://developers.google.com/apps-script/guides/triggers/installable)

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

## Magyarországi szállítás ellenőrzése

A keresés nem indít `getItem`-hívást szállításellenőrzéshez. Ismert HU-díjú tétel `yes`; ismeretlen díjnál a hat órán belüli ellenőrzött `yes`/`no` cache alkalmazható, enélkül `probably_no`. A kliens ezeket a „Valószínűleg nem szállít Magyarországra” csoportban mutatja. A `listing_details` ellenőrzi a `shipToLocations` mezőt és az esetleges HU-díjat, majd hat órára cache-eli. Az `api_calls`, `browse_search_calls`, `get_item_calls` (keresésnél 0) és `oauth_calls` adja a bontást.

## Kontrollerek mérése

1. A forrás feltöltése után nyisd meg vagy frissítsd az Apps Script projekt szerkesztőjét.
2. A **diagnose_controllers.gs** fájlban válaszd a **diagnoseControllers** függvényt, majd kattints a **Futtatás** gombra.
3. A **Végrehajtási napló** tartalmazza a kategóriajavaslatokat, a kulcsszavak tételazonosító-alapú lefedettségét, a kategória nélküli eltéréseket és a címbesorolást. A végén találod a kulcsszójavaslatot és a felhasznált hívások számát.

A mérés németországi tételekkel dolgozik. Keresésenként legfeljebb öt, egyenként 200 tételes oldalt kér le. A javaslatban az országonkénti szám az első oldalas kereséseket mutatja, a német mérés lapozással együtt számolt értéke külön szerepel. A futtatáshoz elegendő a forrás feltöltése.

## Használt állapotú, cím szerint hibás tételek mérése

A forrás feltöltése után a szerkesztőben nyisd meg a **diagnose_used_faulty.gs** fájlt, válaszd a **diagnoseUsedFaulty** függvényt, és kattints a **Futtatás** gombra. A **Végrehajtási naplóban** láthatók az ellenőrzött állapotazonosítók, a keresésenkénti példák és a DE, FR, IT, NL országokra számolt javaslatok. A diagnosztikához elég a forrás feltöltése.

A fő keresés a 7000-es állapotot használja. A `supplementary_search.js` konfiguráció alapján Németországban mindkét eszközcsoporthoz két-két, Franciaországban a kontrollerekhez két kiegészítő keresés fut a mérésben visszaigazolt 3000-es állapottal. Ezek csak cím szerint hibás tételeket adnak, `fault_source: "title"` jelöléssel. Duplikált azonosítónál a fő keresés adata marad meg. A `filtered_not_faulty` az egyes kiegészítő lekérdezésekből cím alapján kihagyott találatok összes száma.

A mérés a német piactér [Metadata API-jával](https://developer.ebay.com/develop/guides/sell/listing-metadata-guide) ellenőrzi az állapotokat. Csak az alkalmazástokennel ténylegesen visszakapott azonosítókat méri. Az eBay egyes felújított állapotokhoz felhasználói tokent igényel. A keresésenkénti ötoldalas korlát és a teljes futás időkorlátja részleges mintát eredményezhet, amit a napló jelöl.

## EUR és HUF

A keresés és a `state_get` válasz az `exchange_rate` mezőben adja az árfolyamot (`eur_huf`, `date`, `source`, `stale`). Az app és a meglévő időzítő budapesti idő szerint 16:30-tól kérhet új jegyzést. Közzétételi időszakonként legfeljebb egy [ECB XML-lekérés](https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml) történik. Hiba esetén a korábbi árfolyam marad elérhető, ha van. A Beállításokban és a keresési összesítőben megjelenik a jegyzés dátuma. Az árszűrők és az értesítési határok EUR-ban szinkronizálódnak.

## Új találatok értesítési szabályai

A Figyelés lapon a szabály neve, eszközcsoportjai, modelljei, hirdetéstípusa, EUR-ban tárolt vételár- és teljesárhatára, szállítási feltétele, aukciózárási időkorlátja, tartalmazó/kizáró címszavai, országai és kizárási kapcsolói szerkeszthetők. A kulcsszavak kis- és nagybetűtől független részszövegek. Az üres modell- vagy országlista az összeset jelenti. Az időkorlát a fix áras tételeket megtartja.

A meglévő szabályok olvasáskor megkapják az új alapértékeket, megtartva az eredeti árhatárt és az ismeretlen szállításra vonatkozó választást. Az új szabály alapból kizárja a „Lehet, hogy nem hibás” tételeket, és bevonja a használtként hirdetett, cím szerint hibás tételeket. Az árhatár üresen korlátlan. Az időzített keresés a szabályok által érintett eszközcsoportokat kéri le, és megtartja a napi 4000-es védelmet.

## Új eszközcsoportok mérése (alkalmazásba építés előtt)

A forrás feltöltése után frissítsd az Apps Script szerkesztőt. Nyisd meg a **diagnose_new_device_groups.gs** fájlt, a függvénylistából válaszd a **diagnoseNewDeviceGroups** függvényt, majd kattints a **Futtatás** gombra. A meglévő Script Properties eBay-kulcsait és azonos engedélyeit használja; a szerkesztőből indított diagnosztikához **nem kell új webapp-verziót telepíteni**.

A mérés a Taxonomy API-val választ kategóriákat, majd a Switch, Steam Deck, iPhone és videokártya kulcsszavait DE, FR és IT országokra futtatja. Összesen 51 első oldalas keresés, 5 Taxonomy-hívás, szükség esetén OAuth, valamint csoportonként legfeljebb 10 getItem szükséges, a lapozáson és az egyszeri 429-es újrapróbálásokon felül. Egy lekérdezés legfeljebb öt oldalt kér le; a diagnosztika a teljes keresési részre 350 hívást és időkorlátot alkalmaz. Minden hívás bekerül a napi számlálóba. Hibánál vagy korlátnál a minta részlegességét jelzi.

A **Végrehajtási naplóban** megtalálod a kategóriajavaslatokat, a kulcsszavak lefedettségét és egyedi hozzájárulását, a címbesorolás példáit, az iCloud-/aktiválásizár-említéseket, a szállítási mintát, a minimális teljes releváns lefedettségű kulcsszókészletet és a hívásbecslést. A releváns halmaz itt csak a címből egyértelműen felismert támogatott modelleket jelenti; a bizonytalan címeket külön számolja. A besorolás diagnosztikai becslés. A zár említése nem igazolt zároltság, az említés hiánya nem igazolt zármentesség.

A szállítási minta az ismeretlen díjú, felismert tételekből váltakozva vesz DE/FR/IT példákat, legfeljebb tízet csoportonként. Ez nem véletlen, reprezentatív minta. Az eleve ismert díjak száma is a felismert támogatott tételekre vonatkozik. A 27 országos hívásbecslés a három mért ország egyszerű kivetítése; az országok eltérő kínálata és a gyorsítótár miatt a tényleges költség eltérhet. A diagnosztika történeti getItem-becslése még a korábbi, keresésenként közös 100-as korlátot feltételezi; az alkalmazás keresése azóta nem indít automatikus szállítási próbát.

**Ezt küldd vissza:** a teljes naplót, különösen az összesítést és a végén kiírt egyetlen JSON-sort. A napló megadja a célfájl nevét: `apps_script/test/fixtures/new_device_titles_live_<dátum>.json`. A JSON kizárólag kitakart példacímeket, országot, eszközcsoportot és diagnosztikai besorolást tartalmaz; a `diagnostic` mező még nem végleges tesztelvárás. Ha a Google a hosszú JSON-sort csonkolja, másold be helyette az összes `FIXTURE_PART_1`, `FIXTURE_PART_2`, … sort is; ezekből minden példacím visszaállítható, majd rögzíthető a fixture-ben. Ne másolj be Script Properties értékeket vagy nyers eBay-választ.

A diagnosztika nem módosítja a keresési csoportokat, nem írja a Sheets/seen lapot, és nem tárol hirdetést gyorsítótárban. Csak a meglévő OAuth-token-cache és a napi hívásszámláló változhat. Az alkalmazás funkciói és buildje változatlanok.

## A kliensnek szánt API

A `POST` JSON-törzse `token`, `action`, `params` és opcionális `request_id` mezőből áll. A felső mérethatár 10 240 bájt. Az egyszerű, legfeljebb 128 karakteres kérésazonosítót a válasz visszaadja. A `doGet` csak az API nevét adja vissza.

| `action` | `params` | `data` |
|---|---|---|
| `ping` | `{}` | `version`, `server_time` |
| `search` | Opcionális `device_groups` (`consoles`, `controllers`, `switch`, `steam_deck`, `iphone`, `gpu`, alapból mind a hat), `countries` ISO-kódokkal (alapból az EU 27 országa), és `queries` a kiválasztott eszközcsoportok kulcsszavaival. | A `listings` és `unknown_shipping` listák tételei `device_group` és `ships_to_hu` besorolással, típus- és szállítási bontás, országonkénti és lekérdezésenkénti állapot, számlálók. |
| `listing_details` | `source_listing_id` az eBay Browse válaszából | `condition_description`, `short_description`, `description_text` vagy `null`; továbbá `ships_to_hu`, `shipping_cost`, `shipping_currency`, `icloud_status`. Egyszerű szövegként jelenítsd meg; a szállítás/zár alapján a kliens frissíti a tételt. |
| `notify_test` | `{}` | A sorba tett próbaértesítés `id` értéke. |
| `notifications_pull` | `device_id` (UUID) | Az eszköz által még nem nyugtázott, érvényes `notifications` lista. |
| `notifications_ack` | `device_id` és az értesítésazonosítókat felsoroló `ids` lista | `acknowledged: true`. |

A `search` esetében az `ok: true` azt jelenti, hogy a keresés állapota kiolvasható a `data` mezőből. A kliens ott ellenőrizze a `status` értékét. A `partial` a keresés hiányosságát, az `error` minden első oldal sikertelenségét jelzi. A pénzösszegek decimális sztringek. A napi számláló a projekten keresztül megkísérelt eBay-hívásokat számolja, budapesti idő szerint.

A Content Service a válaszhoz külön Google URL-t ad. A kliens a POST átirányítását kézzel kezelje, majd a `script.googleusercontent.com` címet GET-tel, az eredeti törzs és token nélkül nyissa meg. [Content Service átirányítás](https://developers.google.com/apps-script/guides/content#redirects)

## Az új eszközcsoportok bekapcsolása

A Flutter keresőjében és az értesítési szabályokban külön választható a Switch, Steam Deck, iPhone és videokártya. Első indításkor a korábbi Konzolok/Kontrollerek kijelölés marad; az újakat külön kapcsold be. A 11–17-es iPhone-ok zárjelölése nem azonos a SIM-zárral. A zárolt készülékek, a nem videokártya tételek és a valószínűleg nem Magyarországra szállítók külön rejtett nézetből megnyithatók. Az ismeretlen díjak korábbi külön blokkja megszűnt.

Az új csoportok kiegészítő használtállapotú keresése még nincs bekapcsolva, csak az üres konfigurációja készült el. A 291 éles cím külön ellenőrzött tesztelvárásai és a bizonytalan esetek döntései: [besorolási feljegyzés](../docs/uj_eszkozcsoportok_besorolas.md).
