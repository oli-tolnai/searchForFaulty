# Console Deal Finder – fejlesztési terv

> **Architektúra (2026. november, mérések alapján döntve):** Flutter-alkalmazás Androidra és Windowsra, Google Apps Script háttérrendszer, Google Sheets adattár, ntfy-értesítések. Részletek: 19. pont. A korábbi Python (FastAPI) + React prototípus (`backend/`, `frontend/`) referencia, nem fejlesztjük tovább.

## 1. A projekt célja

Készíts egy modern, magyar nyelvű alkalmazást **Console Deal Finder** néven, **Androidra és Windowsra** (Flutter), közös, Google Apps Scriptben futó háttérrendszerrel (19. pont).

Az alkalmazás különböző online piactereken hibás, nem működő, részben működő vagy alkatrésznek árult játékkonzolokat keres, és az eredményeket egyetlen áttekinthető felületen listázza.

Az alkalmazás saját használatra készül. A cél a lehető legalacsonyabb fenntartási költség, lehetőség szerint **0 Ft/hó**. Nincs szükség automatikus AI-elemzésre, hibadiagnózisra vagy javíthatósági pontszámra; a felhasználó maga dönti el, érdemes-e megvenni a készüléket.

**Alapelv:** valódi, aktuális, ellenőrizhetően aktív hirdetések jelenjenek meg, ne kitalált, lejárt vagy eladott találatok.

## 2. Támogatott konzolok

Első körben:

- PlayStation 5 (Fat Disc / Digital)
- PlayStation 5 Slim (Disc / Digital)
- PlayStation 5 Pro
- Xbox Series X
- Xbox Series S

A rendszer felépítése tegye lehetővé további eszközök hozzáadását. Tervezett bővítés (6. fázis), a javíthatóság és a kereslet alapján: **Nintendo Switch** (V1, V2, Lite, OLED), majd **Steam Deck**. Apple termékek (MacBook, iPhone) csak később, kötelező „iCloud-/aktiválási zár” jelöléssel („iCloud”, „gesperrt”, „locked”, „Aktivierungssperre”), mert a zárolt készülék gyakorlatilag csak alkatrésznek jó. Minden új eszközcsoport keresésenként kb. +27 eBay-hívás. A modellek (név, eBay-kategória, felismerési szabályok) konfigurációs adatként legyenek tárolva, ne a kódba égetve.

## 3. Hirdetési források

### eBay – elsődleges adatforrás

Az első teljesen működő integráció az eBay legyen, a hivatalos **eBay Browse API** (`item_summary/search`, `getItem`, `getItems`) segítségével, application tokennel (OAuth client credentials). Felhasználói bejelentkezés nem szükséges. A hozzáférés beszerzését a 18. pont írja le.

#### Fő szempont: közvetlenül Magyarországra rendelhető ajánlatok

Az app célja, hogy a hirdetett konzol **plusz költség nélkül, közvetlenül Magyarországra rendelhető** legyen. Ezért:

- Minden eBay-lekérdezés tartalmazza a `deliveryCountry:HU` szűrőt: csak azok a tételek jelennek meg, amelyeket az eladó Magyarországra szállít.
- A kereső a `X-EBAY-C-ENDUSERCTX: contextualLocation=country%3DHU` fejléccel kéri a Magyarországra érvényes szállítási díjat. Az irányítószámos változat mérve nem javított (lásd lent), ezért a `HU_POSTAL_CODE` csak a diagnosztikában használt.
- Csak EU-tagállamban található termék jelenhet meg, mert EU-n belüli vásárlásnál nincs vám és külön ÁFA.
- Csomagtovábbítós (német vagy más külföldi címre történő) rendelés egyelőre nem része a tervnek.

#### Keresési stratégia (élesben mérve, 2026. november)

A stratégia az 1. fázis elején futtatott diagnosztikai mérések eredményén alapul (`backend/scripts/check_ebay.py`, `compare_location_filters.py`, `compare_country_strategy.py`).

**Egy lekérdezés felépítése:**

- Marketplace: `X-EBAY-C-MARKETPLACE-ID: EBAY_DE`
- `q`: modellcsoportonként külön lekérdezés: `ps5` és `xbox series` (konfigurálható lista)
- `category_ids=139971` (Video Game Consoles, Taxonomy API-val ellenőrizve)
- filter: `conditionIds:{7000}` („For parts or not working / Für Bastler”), `buyingOptions:{AUCTION|FIXED_PRICE}`, `deliveryCountry:HU`, `itemLocationCountry:<ország>`
- `limit=200`; ha a `total` nagyobb, lapozás `offset`-tel

**Országonként és modellcsoportonként egy lekérdezés**, alapból mind a 27 EU-tagállamra (27 × 2 = 54 hívás). Az országlista a beállításokban szerkeszthető.

**A mérések, amelyekre a stratégia épül:**

| Kérdés | Eredmény | Döntés |
|---|---|---|
| Működik-e az `itemLocationRegion:EUROPEAN_UNION`? | Nem. `deliveryCountry:HU` mellett az eBay nem támogatja (warning 12519), a szűrőt figyelmen kívül hagyja; a 140 találat mind USA-beli volt. | Nem használjuk. |
| Működik-e az `itemLocationCountry`? | Igen, pontosan: minden találat a megadott országban volt (DE: 60, FR: 20, IT: 13). | Erre épül a földrajzi szűrés. |
| Számít-e a marketplace? | Nem: `EBAY_DE` + `FR` itemId-re pontosan ugyanazt adja, mint `EBAY_FR` + `FR` (az olasznál ugyanígy). | Egyetlen marketplace (`EBAY_DE`) elég. |
| Kell-e kulcsszó? | Igen: kulcsszó nélkül a kategória 1612 találatot adott, a lekért 594-ből csak 3 volt PS5. | A modellnevek a `q`-ba kerülnek. |
| Hol van kínálat? (q=ps5) | DE 60, FR 20, IT 13, NL 1; AT, PL, ES, BE, CZ: 0. | Mind a 27 ország marad alapból, mert egy hívás olcsó, és a ritka találat is érték. |
| Működik-e a VAGY-szintaxis? | Nem: a `(ps5, playstation 5, xbox series)` a DE 73 egyedi tételéből 32-t, a `(ps5,"xbox series")` 23-at adott vissza; a `(ps5,xbox)` 24-et, plusz 188 Xbox One/360/Classic tételt. A `q=playstation 5` azonos a `q=ps5`-tel. | Modellcsoportonként külön lekérdezés (`ps5`, `xbox series`). |
| Pontos-e a `q=ps5`? | Nem teljesen: PS1, PS3, PSP tételek is jönnek. | A modellfelismerés kiszűri a nem támogatott modelleket. |
| Ismert-e a szállítási díj Magyarországra? | A tételek kb. 70%-ánál nem: az eBay 11510-es figyelmeztetést ad („problem calculating the shipping cost”). A kódolatlan, a kódolt és a magyar irányítószámos fejléc, valamint a `getItem` is 0/10 ismert díjat adott ugyanazon a mintán. | Az eBay API korlátja. A kereső a kódolt, irányítószám nélküli fejlécet használja; ezek a tételek „Nem ismert” díjjal, külön blokkban jelennek meg, a díjat a hirdetésben kell megnézni. Becslés tilos. |

**Ellenőrzés a backendben:** az `itemLocationRegion` kiesése miatt is kötelező, hogy a backend minden találatnál ellenőrizze az `itemLocation.country` mezőt egy fix EU-tagállam-listával szemben. Ami nem EU-s, vagy aminek nincs ismert helye, kerüljön ki az aktív listából. Ne keverd össze az eladó országát, a piactér országát és a termék tényleges feladási helyét; a szűrés a termék helyére vonatkozik.

**A válasz `warnings` mezőjét** mindig naplózni és a keresési állapotban jelezni kell, mert egy figyelmen kívül hagyott szűrő csendben hibás eredményt ad.

**Kiegészítő keresés (2. fázis):** vannak eladók, akik „Used / Gebraucht” állapotot adnak meg, de a címben jelzik a hibát („defekt”, „for parts”). Ehhez állapotszűrő nélküli, hibát jelző kulcsszavas lekérdezés fut, de **csak azokra az országokra, ahol a fő keresés talált tételt** (mérés alapján jellemzően 3–5 ország). Ezeknél a találatoknál jelezni kell, hogy a hiba csak a címből derül ki.

#### Hívásszám-keret

A Browse API napi kerete **5000 hívás** (élesben ellenőrizve a Developer Analytics API-val). Egy teljes futás ennek csak kis részét használja:

| Lekérdezés | Darab |
|---|---|
| Fő keresés: 27 ország × 2 lekérdezés (`ps5`, `xbox series`) | 54 |
| Lapozás (ha egy ország `total` értéke > 200) | 0–3 |
| Kiegészítő kulcsszavas keresés (2. fázis, csak a találatot adó országokra) | 3–5 |
| Tárolt tételek státuszellenőrzése `getItems`-szel (20 tétel/hívás, 2. fázis) | tárolt tételek / 20 |

**Cél: egy teljes keresés az alapbeállításokkal < 60 API-hívás.** Napi 5000-es keret mellett ez kb. 80 teljes keresést enged naponta. Az app számolja és jelenítse meg a napi felhasznált hívások számát, és a keret közelében figyelmeztessen.

#### Hirdetési típusok és mezők

Támogatandó hirdetési típusok (`buyingOptions`):

- Fix ár (`FIXED_PRICE`)
- Licitálós aukció (`AUCTION`)
- Ajánlattétel (`BEST_OFFER`), ahol az adatforrás jelzi

Kezelendő mezők: aktuális ár vagy licit (`price` / `currentBidPrice`), licitszám (`bidCount`), aukció vége (`itemEndDate`), hirdetés URL-je (`itemWebUrl`), azonosítója (`itemId`), termék helye (`itemLocation`), szállítási díj (`shippingOptions`), elérhetőség. Ha az API valamelyik adatot nem adja vissza, az app jelezze a hiányt, ne találjon ki értéket.

A magyarországi szállítási díjat a fenti `contextualLocation` fejléc biztosítja. Ha a válaszban mégsem szerepel díj, vagy a díj „számított” (calculated) típusú, értéke: **„Nem ismert”**. A nulla szállítási díj soha ne legyen alapértelmezés.

### Jófogás és HardverApró

Egyik oldalnak sincs nyilvános API-ja, és a felhasználási feltételeik a gépi lekérdezést jellemzően nem engedik. Ezért:

- **Alapmegoldás:** előre kitöltött, megnyitható keresőlinkek a kiválasztott modellekre és a hibát jelző kulcsszavakra („hibás”, „javításra”, „alkatrésznek” stb.).
- Ajánlott kiegészítés: a Jófogás saját „mentett keresés” e-mail értesítőjének használata (ezt a felhasználó a Jófogás oldalán állítja be; az app csak útmutatót ad).
- Automatikus lekérdezés csak akkor készüljön, ha az adott oldal feltételei ezt kifejezetten engedik (pl. hivatalos RSS vagy API). Ezt a 3. fázis elején kell ellenőrizni.

### Facebook Marketplace

Engedélyezett gépi hozzáférés nincs, ezért **nem integráció**, hanem csak előre kitöltött keresőlink. Bejelentkezési, CAPTCHA- vagy hozzáférés-korlátozást az app semmilyen formában ne kerüljön meg.

**Prioritás:** a Jófogás, HardverApró és Marketplace ne blokkolja a működő eBay MVP elkészítését.

## 4. Keresés

A főoldalon legyen jól látható **„Keresés indítása”** gomb. A keresés a bekapcsolt adatforrásokból új, valós adatokat kérdezzen le.

Szűrők:

- Konzolmodellek, többes kijelöléssel
- Maximális vételár
- Maximális teljes ár szállítással együtt
- Pénznem: EUR / HUF
- Termék helye: szűkítés egyes országokra a már letöltött találatokon belül (helyi szűrés, nem extra API-hívás)
- Keresett országok (alapból mind a 27 EU-tagállam; a lista szerkeszthető)
- Aukció / fix ár / mindkettő
- Kiegészítő keresési kulcsszavak szerkesztése

A szűrés a már letöltött találatokon azonnal, új API-hívás nélkül működjön. A beállítások maradjanak meg, és szinkronizálódjanak a két eszköz között (Google Sheets, 19. pont).

## 5. Keresési kulcsszavak

Az elsődleges keresésben a `q` a **modellneveket** tartalmazza (lásd 3. pont). Az alábbi, hibát jelző kulcsszavak a 2. fázis **kiegészítő** kereséséhez és a találatok helyi utószűréséhez kellenek.

**Angol:** faulty, broken, for parts, spares or repair, not working, no display, no power, overheating.

**Német:** defekt, bastler, ersatzteile, reparatur, startet nicht, kein bild, überhitzt, geht nicht an.

**Magyar:** hibás, javításra, alkatrésznek, nem kapcsol be, nincs kép, túlmelegszik, nem működik.

A francia, olasz, spanyol és lengyel kifejezések is legyenek konfigurálhatók.

Az eBay VAGY-szintaxisa (`(a, b, c)`) a mérések szerint megbízhatatlan, ezért ne használd. Néhány célzott, külön lekérdezés fusson, majd az eredmények egyesítése és deduplikálása következzen (`source` + `source_listing_id` alapján).

Zárja ki az egyértelműen önálló kiegészítőket (kontroller, burkolat, doboz, kábel, töltő, alaplap önmagában – utóbbi konfigurálható), de **ne** zárja ki a „console for parts” megfogalmazású, teljes hibás konzolokat.

### Modellfelismerés és tételtípus

Minden találat két címkét kap: **tételtípust** és **modellt**.

**Tételtípus:**

| Típus | Példa | Alapból látható? |
|---|---|---|
| Konzol | „Sony PlayStation 5 Disc Edition Defekt Bastler” | igen |
| Konzol – csomag (több darab) | „Posten 4 Sony PlayStation 5 Konsolen” | igen, jelölve |
| Alaplap | „PS5 Slim EDM-040 Mainboard für Ersatzteile” | nem (szűrővel bekapcsolható) |
| Nem konzol (kiegészítő, üres doboz, szolgáltatás, alkatrész) | „Ps5 Box Leer Anleitung”, „Liquid Metal PS5”, „Reinigung & HDMI” | nem |
| Nem támogatott modell | PS1, PS3, PS4, PSP, Xbox One/360 | nem, csak a darabszám jelenik meg |
| Ellenőrzendő | valóban kétértelmű cím | igen, jelölve |

Fontos: a konzol mellé adott tartozék („Neuer Controller”, „Box und Kabel”, „Fortnite Bundle”) nem teszi a tételt kiegészítővé. Kiegészítőnek csak az számít, ahol a cím a konzol nélküli részre utal (pl. „nur Controller”, „Box leer”, „Mainboard”).

**Modell:** PS5 (Fat), PS5 Slim, PS5 Pro, Xbox Series X, Xbox Series S, kiadással (Disc / Digital), ha felismerhető. A felismerés sorrendje:

1. A hirdetés strukturált tulajdonságai (`localizedAspects`, pl. „Modell”, „Plattform”) – ezek a `getItem` válaszában érhetők el (2. fázis).
2. Címből szabályalapú felismerés (pl. CFI-modellszámok: CFI-10xx/11xx/12xx = Fat, CFI-20xx = Slim, CFI-70xx = Pro; „slim”, „pro”, „digital”, „disc”).
3. Ha a cím biztosan PS5 konzolra utal, de a generáció nem derül ki (pl. „PS5 Disc Edition Defekt”), a modell **„PS5 (változat nem ismert)”** – ez nem ellenőrzendő, csak hiányos adat.

**Kiegészítő jelölés:** „Banned / Gebannt / gesperrt” szó esetén a tétel kapjon **„Tiltott (banned) konzol”** jelölést, mert ez az online használatot érinti.

## 6. Találati lista

Minden hirdetésnél látható:

- Termékkép
- Hirdetés címe
- Konzolmodell (vagy „Ellenőrzendő”)
- Forrás / piactér
- Vételár vagy aktuális licit
- Szállítási költség Magyarországra (vagy „Nem ismert”)
- Teljes ár, csak ha kiszámítható
- Ország / termék helye
- Aukció vagy fix ár
- Licitek száma, ha elérhető
- Aukció lejárata és visszaszámláló, ha releváns
- **„Leírás” gomb:** kattintásra (egy `getItem` hívással) megjelenik az eladó állapotra vonatkozó megjegyzése (`conditionDescription`) és a leírás szövege, eredeti nyelven. Fordítás fizetős API nélkül: **„Fordítás a Google Fordítóval”** gomb (a böngészőben nyitja meg a szöveget, `translate.google.com/?sl=auto&tl=hu&text=…`). A DeepL API Free 2026-ban megszűnt, az Azure Translator beállítása túl bonyolult volt – ezek nem használhatók.
- „Tiltott (banned) konzol”, „Korai licit – a végső ár várhatóan magasabb” (aukció, több mint 2 nap van hátra) és „Lehet, hogy nem hibás” jelölés (a cím új állapotra utal, hibára utaló szó nélkül; a tétel nem rejtendő el)
- Jelzés, ha a hiba csak a címből/leírásból derül ki (nem „For parts” állapotú)
- **„Utoljára ellenőrizve: …”** időpont
- Közvetlen eredeti hirdetéslink

A kártyáról lehessen megnyitni az eredeti hirdetést (a rendszer böngészőjében). Ne generálj hamis linkeket vagy termékazonosítókat.

## 7. Rendezés és szűrés

Rendezések:

- Legolcsóbb előre
- Legdrágább előre
- Legújabb hirdetések
- Leghamarabb záródó aukciók
- Legalacsonyabb ismert teljes ár szállítással

Szűrők: konzolmodell, piactér, ország, ár, hirdetési típus. Legyen keresőmező a már letöltött találatok között.

Teljes ár szerinti rendezésnél az ismeretlen szállítású hirdetések **a lista végére kerüljenek, külön „Ismeretlen szállítási díj” fejléc alá**. A szállítást soha ne tekintsd ingyenesnek.

## 8. Kedvencek és elrejtett hirdetések

Minden hirdetésnél:

- **Kedvencekhez adás** – mentés saját listába
- **Elrejtés** – ne jelenjen meg a normál eredmények között, de visszaállítható legyen

Legyen külön **Kedvencek** és **Elrejtett hirdetések** oldal. A mentések a Google Sheetsben tárolódnak, újraindítás után is megmaradnak, és a telefonon és a gépen ugyanazok (19. pont).

A kedvencek oldalon is látszódjon a státusz: a lejárt/eladott kedvenc maradjon a kedvencek között, de egyértelműen „Lejárt / nem elérhető” jelöléssel.

A duplikáció kezelése az eredeti forrás + hirdetésazonosító alapján történjen, hogy ugyanaz a tétel több kulcsszavas keresésből ne szerepeljen többször.

## 9. Új hirdetések jelölése

Egy hirdetés akkor **„ÚJ”**, ha a `source` + `source_listing_id` páros **egyetlen korábbi keresésben sem** szerepelt (a keresési szűrőktől függetlenül). Az első keresési futás után minden találat „látott” lesz; az első futás találatai nem kapnak „ÚJ” jelölést, hanem a felület jelezze, hogy ez az első szinkronizálás.

Az „ÚJ” jelölés a következő keresésig marad meg, vagy amíg a felhasználó meg nem nyitja a hirdetést.

Aukciós árak változásakor frissüljön az aktuális licit. A már látott hirdetések ne kapjanak automatikusan új címkét pusztán árfrissítés miatt (opcionálisan „Ár változott” jelölés kaphatnak).

A találatok elérhetőségét ellenőrizni kell, hogy az eladott, törölt vagy lejárt tételek ne maradjanak az aktív listában (részletesen a 17. pontban).

## 10. Felhasználói felület

Modern, letisztult, **sötét témájú**, magyar nyelvű **Flutter-alkalmazás** Androidra és Windowsra, telefonos és asztali elrendezéssel. Böngészőben futó változat (és PWA) nem készül; a böngészőt csak az eredeti hirdetés és a fordítás megnyitására használja.

Fő képernyők / elemek:

1. Navigáció: Keresés, Kedvencek, Figyelt aukciók, Elrejtett, Beállítások
2. Szűrők és keresési beállítások
3. Kiemelt **Keresés indítása** gomb, a keresés idejére állapotjelzővel
4. Összesítő: találatok száma (szűrt / összes), típusonként kiszűrt tételek, API-hívások, a keresés időpontja
5. Kártyás eredménylista, a végén az „Ismeretlen szállítási díj” blokk
6. Figyelés beállítása egy aukcióra (értesítési határár, 20. pont)
7. Beállítások: Apps Script webapp-cím és titkos token (biztonságos tárolóban), ntfy-csatorna neve
8. Később: magyar piacterek keresőlinkjei (Jófogás, HardverApró, Facebook Marketplace)

A keresés közben jelenjen meg a folyamat állapota, utána a forrásonkénti siker/hiba, hogy egy részlegesen sikeres futás ne tűnjön teljesnek.

## 11. Technológia

- **Kliens:** Flutter (Dart), Android és Windows, egy kódbázisból
- **Háttérrendszer:** Google Apps Script (V8 JavaScript), a felhasználó privát Google-projektjében, webapp-végponttal és időzített triggerekkel
- **Adattár:** Google Sheets (a felhasználó saját táblázata)
- **Értesítés:** ntfy (ingyenes Android-app, HTTP-ből küldhető)
- **Adatforrás:** eBay Browse API
- **Árfolyam:** Európai Központi Bank napi referencia-árfolyama (ingyenes), kézi felülírási lehetőséggel
- **Fejlesztés:** az Apps Script-kód a repóban (`apps_script/`), Node.js alatti tesztekkel, feltöltés `clasp`-pal; a Flutter-kód a `flutter_app/` mappában

Az eBay-kulcsok kizárólag az Apps Script **Script Properties** tárában vannak; a kliensbe, a táblázatba, a repóba és a naplóba nem kerülhetnek. A kliens csak a webapp címét és egy saját titkos tokent ismeri, ezeket a rendszer biztonságos tárolójában őrzi (`flutter_secure_storage`).

Ne használj fizetős AI API-t vagy fizetős szolgáltatást. A rendszer 0 Ft/hó: az eBay Browse API alapkeretben, az Apps Script és a Sheets fogyasztói Google-fiókkal, az ntfy publikus szolgáltatása és az ECB-árfolyam ingyenes. Saját szervert nem üzemeltetünk.

## 12. Működés internet nélkül

A Flutter-app az utolsó sikeres keresés eredményét és a szinkronizált állapotot helyben gyorsítótárazza, így internet nélkül is megjeleníthetők, de **kizárólag egyértelmű „Korábban mentett / offline” jelzéssel**. Offline módosítás (kedvenc, elrejtés) helyben sorba kerül, és a következő kapcsolódáskor szinkronizálódik.

Új kereséshez és az elérhetőség aktuális ellenőrzéséhez internet szükséges. Offline állapotban a régi találatokat nem szabad frissen ellenőrzött, aktív ajánlatként feltüntetni.

## 13. Technikai és hibakezelési követelmények

- Párhuzamos, de API-korlátokat tiszteletben tartó lekérdezés (Apps Scriptben `UrlFetchApp.fetchAll` kötegekben; a telepített webappon át mérve a teljes keresés 8-as kötegekkel 9,2 mp, 4-es kötegekkel 15 mp, hiba nélkül; a webapp pingje 1–2 mp)
- Hálózati hibák, rate limit (HTTP 429) és időtúllépések kezelése, exponenciális visszalépéssel
- Napi API-hívásszám nyilvántartása
- Deduplikáció
- Hiányzó képek, árak, szállítási adatok kezelése
- EUR/HUF átváltás az ECB árfolyamával vagy kézzel állítható árfolyammal; az alkalmazott árfolyam és dátuma megjelenik a felületen
- Forrásonkénti keresési állapot
- Naplózás, de a titkos kulcsok és tokenek kitakarásával
- Kizárólag valós, ellenőrizhető találatok
- Biztonságos hitelesítési és konfigurációkezelés
- Eladói személyes adatot (felhasználónév, értékelés) se a Sheets, se az Apps Script naplója vagy gyorsítótára, se a kliens, se az értesítés ne tartalmazzon (lásd 18. pont, adattárolási mentesség)
- Tesztek a szűréshez, EU-helyszűréshez, deduplikációhoz, modellfelismeréshez, árkalkulációhoz és státuszkezeléshez

Ha egy piactér lekérdezése sikertelen, az app **ne** állítsa, hogy a keresés sikeres volt az adott oldalon.

## 14. Fejlesztési sorrend

### 0. fázis – mérések és prototípus (kész)

Élesben kimért eBay-keresési stratégia (3. pont), Python (FastAPI) backend és React webes felület prototípusként, Apps Script-mérés (54 hívás párhuzamosan 10 mp alatt, hiba nélkül), architektúra-vizsgálat (`docs/architektura_vizsgalat.md`). A prototípus a portolás referenciája, nem fejlesztjük tovább.

### 1. fázis – Apps Script háttérrendszer

A prototípus keresési logikájának átírása Apps Scriptre: eBay-hitelesítés, országonkénti és modellcsoportonkénti keresés, normalizálás, modellfelismerés és tételtípus, EU-ellenőrzés, deduplikáció, hívásszámláló. Webapp-végpont titkos tokenes hitelesítéssel. Node.js-tesztek, feltöltés `clasp`-pal. A webapp válaszidejének mérése.

### 2. fázis – Flutter-kliens (Android és Windows)

A prototípus felületének megfelelő keresőképernyő: szűrők a letöltött találatokon, rendezés, kártyák, ismeretlen szállítású blokk, visszaszámláló, jelölések, „Leírás” gomb fordítási linkkel, eredeti hirdetés megnyitása a böngészőben. Webapp-cím és token biztonságos tárolása, offline gyorsítótár. Telepítés: Androidra `.apk`, Windowsra futtatható build.

### 3. fázis – közös állapot és életciklus

Google Sheets: kedvencek, elrejtés, már látott tételek („ÚJ” jelölés), beállítások, revíziós szinkron a két eszköz között. Mentett tételek státuszellenőrzése (`getItems`/`getItem`), frissességi szabályok (17.4).

### 4. fázis – értesítések

Aukciófigyelés határárral és ntfy-értesítés (20. pont). Utána időzített keresés és értesítés új, feltételeknek megfelelő találatról.

### 5. fázis – kiegészítések

Kiegészítő kulcsszavas keresés (állapotszűrő nélkül, csak a találatot adó országokra), EUR/HUF átváltás, magyar piacterek keresőlinkjei, `localizedAspects`-alapú modellfelismerés.

### 6. fázis – új eszközök

Nintendo Switch, Steam Deck; később esetleg Apple (2. pont).

## 15. Átadási és elfogadási feltételek

A projekt csak akkor kész, ha:

1. A **Keresés indítása** gomb valós eBay API-lekérést indít.
2. Megjeleníthetők aktív licitálós és fix áras hirdetések.
3. A termék tényleges helye EU-tagállam, ellenőrzött adattal (`itemLocation.country`).
4. A maximális ár szerinti szűrés helyes.
5. Minden megjelenített hirdetéshez valódi, működő eredeti URL tartozik.
6. A kedvencek és elrejtések újraindítás után is megmaradnak, és a két eszközön ugyanazok.
7. Nincsenek kitalált vagy bemutató találatok az éles keresési listában.
8. API-hiba esetén érthető hibaüzenetet ad.
9. A teljes kezelőfelület magyar nyelvű.
10. Dokumentált lépésekkel telepíthető: az Apps Script-projekt `clasp`-pal, az app Androidra (`.apk`) és Windowsra.
11. Lejárt, eladott és nem ellenőrizhetően aktív hirdetés nem szerepel az aktív keresési eredmények között.
12. Egy teljes keresés 60 API-hívás alatt marad az alapbeállításokkal.
13. A figyelt aukcióról értesítés érkezik a telefonra, akkor is, ha az app nincs megnyitva.

## 16. Elvárások a fejlesztővel szemben

**Ne csak dizájnt, látványtervet vagy statikus demót készíts; működő, futtatható alkalmazást.**

Hozd létre:

- Teljes Apps Script- és Flutter-forráskód
- Táblázatséma (munkalapok és oszlopok) és adatkezelés
- A Script Properties és a kliensbeállítások leírása (titkos értékek nélkül)
- Függőségek / telepítőparancsok
- Automatizált tesztek (az eBay-válaszokat a tesztekben rögzített mintaválaszok helyettesíthetik, de az éles alkalmazásban soha nem jelenhet meg demóadat)
- `README.md` részletes indítási útmutatóval
- Az eBay API-regisztráció lépései (18. pont) a README-ben

Valós integrációt használj, ne demóadatokat. Ha valamihez nincs kulcs, vagy az API nem biztosít egy kért funkciót, ezt világosan írd le, és készíts korrekt részmegoldást; ne szimuláld kész funkcionalitásként.

Fázisonként dolgozz, minden fázis végén indítsd és teszteld a rendszert. Az elsődleges cél a **működő eBay-kereső**.

## 17. Kötelező követelmény: lejárt és eladott hirdetések kizárása

**Az aktív találati listában kizárólag aktuálisan aktív, ellenőrizhetően megvásárolható vagy licitálható hirdetések jelenjenek meg.** A lejárt, eladott, lezárt, törölt vagy már nem elérhető tételek ne szerepeljenek benne.

### 17.1. eBay aukciók

- Csak aktív aukciókat mutasson.
- A lejárat legyen későbbi, mint az aktuális idő.
- A lezárt aukciókat távolítsa el az aktív listából.
- Ha egy aukció idő előtt lezárul, az állapotfrissítés után tűnjön el.
- A hátralévő időt jelenítse meg. Amikor a visszaszámláló eléri a nullát, az aukció **azonnal kerüljön ki az aktív listából**, további ellenőrzés nélkül.

### 17.2. Fix áras hirdetések

- Ellenőrizze az aktuális megvásárolhatóságot és készletet (`estimatedAvailabilities`), amennyiben az adatforrás jelzi.
- Az `OUT_OF_STOCK` és `TEMPORARILY_UNAVAILABLE` állapotú, valamint a `getItem`/`getItems` által nem található (lezárt, törölt) tételeket zárja ki.
- Többdarabos hirdetés csak pozitív, elérhető készlet mellett maradjon aktív, ha a piactér ezt az adatot szolgáltatja.

### 17.3. Jófogás és HardverApró

Mivel ezek a források keresőlinkként jelennek meg, az app ezekről nem tárol hirdetést, így státuszt sem kell kezelnie. Ha később engedélyezett automatikus lekérdezés készül, ugyanazok a szabályok érvényesek: az eladott, törölt, archivált és inaktív hirdetés ne jelenjen meg, és ellenőrizhetetlen státusz esetén ne legyen aktívként mutatva.

### 17.4. Elérhetőségi státuszok és frissesség

Tárolandó mezők:

- `status`: `ACTIVE`, `ENDED`, `UNKNOWN`
- `last_checked_at`: az utolsó sikeres állapotellenőrzés időpontja
- `source`, `source_listing_id`, `listing_url`
- `end_time`, ahol van
- `last_check_error`, `last_check_error_at`: az esetleges állapotellenőrzési hiba és annak ideje

A normál aktív találati listába **csak `ACTIVE`** státusz kerülhet.

**Frissességi szabályok (konfigurálható alapértékek):**

- Az aktuális keresés találatai eleve aktívak: `ACTIVE`, `last_checked_at = most`.
- A tárolt, de az aktuális keresésben nem szereplő tételek státuszát az Apps Script `getItems` hívással (20 tétel/hívás) ellenőrzi minden keresés során.
- Ha a `last_checked_at` **2 óránál régebbi**, a tétel automatikusan `UNKNOWN`, amíg újra nem ellenőrzik. (Az eBay API License Agreement 8.1 pontja szerint a megjelenített hirdetési adat legfeljebb 6 órával maradhat el az eBay-en láthatótól; a 2 órás határ ennél szigorúbb.)
- Aukciónál, ha `end_time` < most: azonnal `ENDED`.
- API-hiba, időtúllépés vagy ismeretlen válasz esetén a státusz `UNKNOWN`, soha nem marad megalapozatlanul `ACTIVE`.

Külön „Nem ellenőrizhető / archív” nézet készülhet, de az elemek ott egyértelműen legyenek elkülönítve az aktív ajánlatoktól.

### 17.5. Újrahirdetés és státuszváltozás

Ha ugyanazt a konzolt az eladó új hirdetésazonosítóval ismét meghirdeti, megjelenhet új találatként. Ha egy korábban mentett hirdetés időközben lejárt, ne maradjon bent a fő keresési listában.

### 17.6. Elfogadási tesztek

- Lejárt aukció nem jelenhet meg az aktív találatok között.
- Eladott fix áras hirdetés nem jelenhet meg.
- Törölt hirdetés nem jelenhet meg.
- Ismeretlen állapotú hirdetés nem jelenhet meg aktívként.
- 2 óránál régebben ellenőrzött hirdetés nem jelenhet meg aktívként.
- A korábban eltárolt, később lezárt hirdetés eltűnik az aktív listából.
- A keresési futás friss státuszt ellenőriz, amennyiben az API lehetővé teszi.
- A hirdetésnél látszik: **„Utoljára ellenőrizve: …”**.

**Fontos megkötés:** 100%-os, másodpercre pontos elérhetőség nem garantálható, mert egy hirdetést az ellenőrzés után is megvehetnek. A rendszer törekedjen a legfrissebb állapotra, és a bizonytalanságot mindig jelezze.

## 18. eBay API-hozzáférés beszerzése

Az eBay Developer Program és a Browse API alapkerete **ingyenes**. Lépések:

1. **Regisztráció** a [developer.ebay.com](https://developer.ebay.com) oldalon (meglévő eBay-fiókkal is lehet). A jóváhagyás általában azonnali, de akár 1 munkanapig is tarthat.
2. **Alkalmazás létrehozása** az „Application Keys” oldalon. Két kulcskészlet jár hozzá: *Sandbox* (tesztadatok) és *Production* (éles adatok). Ehhez az apphoz a **Production** kell, mert a Sandboxban nincsenek valódi hirdetések.
3. **Account Deletion értesítés kezelése.** Az eBay minden éles kulcskészlettől megköveteli, hogy vagy feliratkozzon a *Marketplace Account Deletion* értesítésekre (ehhez nyilvánosan elérhető HTTPS-végpont kell), vagy **mentességet kérjen**. Mivel ez az app eladói személyes adatot nem tárol, a mentesség kérhető: Production kulcskészlet → *Notifications / Alerts* → „Marketplace Account Deletion” → *opt out*, az indoklásnál a „nem tárolok eBay-felhasználói adatot” jellegű opciót választva. Amíg ez nincs kész, a Production kulcskészlet „Non Compliant” állapotban le van tiltva.
   - Ha a mentességet nem fogadják el: tartalékmegoldásként egy ingyenes, kis méretű nyilvános végpont (pl. Cloudflare Workers ingyenes csomag) fogadhatja az értesítéseket. Ez nem része az MVP-nek.
4. **Kulcsok bemásolása** a backend `.env` fájljába: `EBAY_CLIENT_ID` (App ID) és `EBAY_CLIENT_SECRET` (Cert ID). A Dev ID-ra nincs szükség.
5. A backend ezekkel **application tokent** kér (`POST https://api.ebay.com/identity/v1/oauth2/token`, `grant_type=client_credentials`, scope: `https://api.ebay.com/oauth/api_scope`). Felhasználói bejelentkezés vagy eBay-jelszó nem kell.
6. **Ellenőrzés:** a README-ben leírt teszt-szkript egy próba-keresést futtat, és kiírja, hogy a kulcsok működnek-e.

A használat során be kell tartani az eBay API License Agreement feltételeit, különösen a lekért adatok tárolására és megjelenítésére vonatkozó szabályokat; ezt az 1. fázis elején át kell nézni.

## 19. Architektúra: Apps Script + Google Sheets + Flutter

**Döntés indoklása (mérések és `docs/architektura_vizsgalat.md` alapján):** ingyenes, mindig futó tárhely nincs kényelmes formában; a felhasználó Xiaomi telefonja agresszíven korlátozza a háttérfeladatokat, ezért az aukciófigyelést a telefontól függetlenül, a Google szerverén kell futtatni. Az Apps Script ingyenes, nem kell szervert üzemeltetni, és a mérés szerint egy teljes keresés 10 mp (54 hívás, `fetchAll`, 4-es kötegek, 0 hiba).

```
 Telefon (Flutter) ─┐                         ┌─ eBay Browse API
                    ├─► Apps Script webapp ───┤
 Gép (Flutter)     ─┘   + időzített triggerek └─ ntfy → telefon
                              │
                       Google Sheets (állapot)
```

**Apps Script (háttérrendszer):**
- Webapp (`doPost`, JSON): keresés, hirdetés részletei, állapot olvasása/írása. Tulajdonosként fut, „Anyone” hozzáféréssel; **minden kérést először egy legalább 256 bites titkos tokennel kell hitelesíteni** (a POST törzsében), mielőtt Sheets vagy eBay elérés történne. Ismeretlen művelet, túl nagy kérés vagy hibás token → azonnali elutasítás.
- Időzített triggerek: aukciófigyelő (5–15 percenként, csak a figyelt aukciókra, üres listánál azonnal kilép), később ritkább (pl. 2 óránkénti) időzített keresés.
- Titkok: `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, a kliens-token(ek) és az ntfy-csatorna neve a Script Properties-ben. Az eBay-token a CacheService-ben, lejáratig.
- Hívásszámláló a Script Properties-ben (napi bontás), közös a két eszköz és a triggerek között.

**Ismert keretek (fogyasztói Google-fiók):** UrlFetch 20 000/nap, egy futás max. 6 perc, időzített futások összesen 90 perc/nap, trigger legkisebb gyakorisága 1 perc. Az eBay napi 5000-es Browse-kerete a szűkebb: óránkénti teljes keresés kb. 1300 hívás/nap, ezért az időzített keresés legfeljebb óránként fusson.

**Google Sheets (adattár):** munkalapok pl. `favorites`, `hidden`, `seen`, `watches`, `settings`, `listings_cache`. Kulcs: `source` + `source_listing_id`. Írás `LockService.getScriptLock()` alatt, kötegelten (`setValues`), revízióval és törlésjelöléssel a két eszköz ütközéseihez, kliens által generált műveletazonosítóval az ismételt írások ellen. A szöveges mezők (pl. cím) képletként való értelmezését meg kell akadályozni. Nyers eBay-választ nem tárolunk; eladói adatot soha.

**Flutter-kliens:** a webapp `/exec` POST-ja átirányítással (302/303 a `script.googleusercontent.com`-ra) válaszol; a klienst úgy kell megírni, hogy az első POST-on ne kövesse automatikusan az átirányítást, hanem a megadott hostra GET-tel kérje le a választ, az eredeti törzs és token továbbküldése nélkül. A választ (JSON) validálni kell; HTML vagy Google-bejelentkezési oldal hibának számít.

**Licenc:** az eBay API License Agreement nem tiltja, hogy a hívások felhőszolgáltatásból menjenek; a kulcs a felhasználó privát projektjében van, harmadik félnek nem adjuk át. A frissességi (8.1) és az eladói adatokra vonatkozó szabályok (18. pont) Sheetsben, Apps Scriptben, kliensben és értesítésben egyaránt érvényesek.

## 20. Értesítések és aukciófigyelés

- **Figyelés beállítása:** egy aukciós kártyán „Figyelés” → határár megadása (pl. 150 €). A figyelés a `watches` munkalapra kerül.
- **Ellenőrzés:** az Apps Script trigger 5–15 percenként `getItems` (vagy kevés tételnél `getItem`) hívással lekéri a figyelt aukciók aktuális licitjét és záró időpontját.
- **Értesítési szabály (alapértelmezés):** ha az aukció aznap (budapesti idő szerint) zárul, a zárásig legfeljebb 2 óra van hátra, és az aktuális licit (ismert, EUR) a határár alatt van → egy értesítés aukciónként. Lezárt aukciónál a figyelés automatikusan lezárul.
- **Csatorna: ntfy.** A felhasználó telepíti az ntfy Android-appot, és feliratkozik egy hosszú, véletlenszerű csatornanévre (pl. `cdf-` + 20 véletlen karakter). Az Apps Script HTTPS POST-tal küld, `Cache: no` fejléccel (az ntfy ne tárolja az üzenetet). Az ntfy-appnak akkumulátor-kivételt kell adni a Xiaomi beállításaiban.
- **Tartalom:** rövid cím, aktuális licit, határár, zárási idő és az eBay-hirdetés linkje (pl. „Ma 19:30-kor zárul: PS5 Slim Digital – 120 € (határ: 150 €)”). Eladói adat nem kerülhet bele.
- **Később:** értesítés új, megadott feltételeknek (modell, max. teljes ár) megfelelő találatról, az időzített keresés alapján.
