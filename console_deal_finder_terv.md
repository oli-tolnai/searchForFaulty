# Console Deal Finder – fejlesztési terv

## 1. A projekt célja

Készíts egy modern, magyar nyelvű, reszponzív webalkalmazást **Console Deal Finder** néven.

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

A rendszer felépítése tegye lehetővé további modellek hozzáadását, például Nintendo Switch, Switch OLED és Steam Deck. A modellek (név, eBay-kategória, felismerési szabályok) konfigurációs adatként legyenek tárolva, ne a kódba égetve.

## 3. Hirdetési források

### eBay – elsődleges adatforrás

Az első teljesen működő integráció az eBay legyen, a hivatalos **eBay Browse API** (`item_summary/search`, `getItem`, `getItems`) segítségével, application tokennel (OAuth client credentials). Felhasználói bejelentkezés nem szükséges. A hozzáférés beszerzését a 18. pont írja le.

#### Fő szempont: közvetlenül Magyarországra rendelhető ajánlatok

Az app célja, hogy a hirdetett konzol **plusz költség nélkül, közvetlenül Magyarországra rendelhető** legyen. Ezért:

- Minden eBay-lekérdezés tartalmazza a `deliveryCountry:HU` szűrőt: csak azok a tételek jelennek meg, amelyeket az eladó Magyarországra szállít.
- Minden lekérdezés a `X-EBAY-C-ENDUSERCTX: contextualLocation=country=HU` fejléccel fut, így a válaszban a Magyarországra érvényes szállítási díj szerepel.
- Csak EU-tagállamban található termék jelenhet meg, mert EU-n belüli vásárlásnál nincs vám és külön ÁFA.
- Csomagtovábbítós (német vagy más külföldi címre történő) rendelés egyelőre nem része a tervnek.

#### Keresési stratégia (élesben mérve, 2026. november)

A stratégia az 1. fázis elején futtatott diagnosztikai mérések eredményén alapul (`backend/scripts/check_ebay.py`, `compare_location_filters.py`, `compare_country_strategy.py`).

**Egy lekérdezés felépítése:**

- Marketplace: `X-EBAY-C-MARKETPLACE-ID: EBAY_DE`
- `q`: minden támogatott modell egyetlen lekérdezésben, az eBay VAGY-szintaxisával, pl. `(ps5, playstation 5, xbox series)`. A pontos kifejezéslista konfigurálható.
- `category_ids=139971` (Video Game Consoles, Taxonomy API-val ellenőrizve)
- filter: `conditionIds:{7000}` („For parts or not working / Für Bastler”), `buyingOptions:{AUCTION|FIXED_PRICE}`, `deliveryCountry:HU`, `itemLocationCountry:<ország>`
- `limit=200`; ha a `total` nagyobb, lapozás `offset`-tel

**Országonként egy lekérdezés**, alapból mind a 27 EU-tagállamra. Az országlista a beállításokban szerkeszthető.

**A mérések, amelyekre a stratégia épül:**

| Kérdés | Eredmény | Döntés |
|---|---|---|
| Működik-e az `itemLocationRegion:EUROPEAN_UNION`? | Nem. `deliveryCountry:HU` mellett az eBay nem támogatja (warning 12519), a szűrőt figyelmen kívül hagyja; a 140 találat mind USA-beli volt. | Nem használjuk. |
| Működik-e az `itemLocationCountry`? | Igen, pontosan: minden találat a megadott országban volt (DE: 60, FR: 20, IT: 13). | Erre épül a földrajzi szűrés. |
| Számít-e a marketplace? | Nem: `EBAY_DE` + `FR` itemId-re pontosan ugyanazt adja, mint `EBAY_FR` + `FR` (az olasznál ugyanígy). | Egyetlen marketplace (`EBAY_DE`) elég. |
| Kell-e kulcsszó? | Igen: kulcsszó nélkül a kategória 1612 találatot adott, a lekért 594-ből csak 3 volt PS5. | A modellnevek a `q`-ba kerülnek. |
| Hol van kínálat? (q=ps5) | DE 60, FR 20, IT 13, NL 1; AT, PL, ES, BE, CZ: 0. | Mind a 27 ország marad alapból, mert egy hívás olcsó, és a ritka találat is érték. |

**Ellenőrzés a backendben:** az `itemLocationRegion` kiesése miatt is kötelező, hogy a backend minden találatnál ellenőrizze az `itemLocation.country` mezőt egy fix EU-tagállam-listával szemben. Ami nem EU-s, vagy aminek nincs ismert helye, kerüljön ki az aktív listából. Ne keverd össze az eladó országát, a piactér országát és a termék tényleges feladási helyét; a szűrés a termék helyére vonatkozik.

**A válasz `warnings` mezőjét** mindig naplózni és a keresési állapotban jelezni kell, mert egy figyelmen kívül hagyott szűrő csendben hibás eredményt ad.

**Ellenőrizendő az eBay-adapter megírásakor:** hogy a VAGY-szintaxisú `q` legalább ugyanazokat a tételeket adja-e vissza, mint a modellenkénti külön lekérdezések (pl. a `q=ps5` 60 találata mind benne van-e).

**Kiegészítő keresés (2. fázis):** vannak eladók, akik „Used / Gebraucht” állapotot adnak meg, de a címben jelzik a hibát („defekt”, „for parts”). Ehhez állapotszűrő nélküli, hibát jelző kulcsszavas lekérdezés fut, de **csak azokra az országokra, ahol a fő keresés talált tételt** (mérés alapján jellemzően 3–5 ország). Ezeknél a találatoknál jelezni kell, hogy a hiba csak a címből derül ki.

#### Hívásszám-keret

A Browse API napi kerete **5000 hívás** (élesben ellenőrizve a Developer Analytics API-val). Egy teljes futás ennek csak kis részét használja:

| Lekérdezés | Darab |
|---|---|
| Fő keresés: 27 ország × 1 lekérdezés | 27 |
| Lapozás (ha egy ország `total` értéke > 200) | 0–3 |
| Kiegészítő kulcsszavas keresés (2. fázis, csak a találatot adó országokra) | 3–5 |
| Tárolt tételek státuszellenőrzése `getItems`-szel (20 tétel/hívás, 2. fázis) | tárolt tételek / 20 |

**Cél: egy teljes keresés az alapbeállításokkal < 50 API-hívás.** Az app számolja és jelenítse meg a napi felhasznált hívások számát, és a keret közelében figyelmeztessen.

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

A beállítások maradjanak meg a következő megnyitásra (SQLite-ban a backendben).

## 5. Keresési kulcsszavak

Az elsődleges keresésben a `q` a **modellneveket** tartalmazza (lásd 3. pont). Az alábbi, hibát jelző kulcsszavak a 2. fázis **kiegészítő** kereséséhez és a találatok helyi utószűréséhez kellenek.

**Angol:** faulty, broken, for parts, spares or repair, not working, no display, no power, overheating.

**Német:** defekt, bastler, ersatzteile, reparatur, startet nicht, kein bild, überhitzt, geht nicht an.

**Magyar:** hibás, javításra, alkatrésznek, nem kapcsol be, nincs kép, túlmelegszik, nem működik.

A francia, olasz, spanyol és lengyel kifejezések is legyenek konfigurálhatók.

Kulcsszócsoportok: egy lekérdezésbe több rokon kifejezés kerülhet az eBay `(a, b, c)` VAGY-szintaxisával, így kevesebb hívás kell. Ne egyetlen túl hosszú lekérdezésre épüljön a keresés: néhány célzott lekérdezés fusson, majd az eredmények egyesítése és deduplikálása következzen (`source` + `source_listing_id` alapján).

Zárja ki az egyértelműen önálló kiegészítőket (kontroller, burkolat, doboz, kábel, töltő, alaplap önmagában – utóbbi konfigurálható), de **ne** zárja ki a „console for parts” megfogalmazású, teljes hibás konzolokat.

### Modellfelismerés

A PS5 Fat / Slim / Pro és a Disc / Digital változat a címből gyakran nem dönthető el. A felismerés sorrendje:

1. A hirdetés strukturált tulajdonságai (`localizedAspects`, pl. „Modell”, „Plattform”, „Model”) – ezek a `getItem` válaszában érhetők el.
2. Címből és leírásrészletből szabályalapú felismerés (pl. CFI-modellszámok: CFI-10xx/11xx = Fat, CFI-20xx = Slim, CFI-70xx = Pro).
3. Ha egyik sem egyértelmű: **„Ellenőrzendő”** jelölés. Bizonytalan esetben inkább ellenőrzendő legyen, mint tévesen besorolt.

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
- Rövid hibaleírás / leírásrészlet
- Jelzés, ha a hiba csak a címből/leírásból derül ki (nem „For parts” állapotú)
- **„Utoljára ellenőrizve: …”** időpont
- Közvetlen eredeti hirdetéslink

A kártyáról lehessen megnyitni az eredeti hirdetést. Ne generálj hamis linkeket vagy termékazonosítókat.

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

Legyen külön **Kedvencek** és **Elrejtett hirdetések** oldal. A mentések alkalmazás-újraindítás után is maradjanak meg (SQLite).

A kedvencek oldalon is látszódjon a státusz: a lejárt/eladott kedvenc maradjon a kedvencek között, de egyértelműen „Lejárt / nem elérhető” jelöléssel.

A duplikáció kezelése az eredeti forrás + hirdetésazonosító alapján történjen, hogy ugyanaz a tétel több kulcsszavas keresésből ne szerepeljen többször.

## 9. Új hirdetések jelölése

Egy hirdetés akkor **„ÚJ”**, ha a `source` + `source_listing_id` páros **egyetlen korábbi keresésben sem** szerepelt (a keresési szűrőktől függetlenül). Az első keresési futás után minden találat „látott” lesz; az első futás találatai nem kapnak „ÚJ” jelölést, hanem a felület jelezze, hogy ez az első szinkronizálás.

Az „ÚJ” jelölés a következő keresésig marad meg, vagy amíg a felhasználó meg nem nyitja a hirdetést.

Aukciós árak változásakor frissüljön az aktuális licit. A már látott hirdetések ne kapjanak automatikusan új címkét pusztán árfrissítés miatt (opcionálisan „Ár változott” jelölés kaphatnak).

A találatok elérhetőségét ellenőrizni kell, hogy az eladott, törölt vagy lejárt tételek ne maradjanak az aktív listában (részletesen a 17. pontban).

## 10. Felhasználói felület

Modern, letisztult, **sötét témájú**, magyar nyelvű, mobilon és asztali gépen is használható felület.

Főoldali elemek:

1. Felső navigáció (Keresés, Kedvencek, Elrejtett, Beállítások)
2. Szűrők és keresési beállítások
3. Kiemelt **Keresés indítása** gomb
4. Találatok száma
5. Kártyás vagy táblázatos eredménylista
6. Lapozás vagy „Továbbiak betöltése”
7. Magyar piacterek keresőlinkjei (Jófogás, HardverApró, Facebook Marketplace) külön blokkban
8. Napi API-hívásszám kijelzése

A keresés közben jelenjen meg a folyamat állapota és a forrásonkénti siker/hiba, hogy egy részlegesen sikeres futás ne tűnjön teljesnek.

## 11. Technológia

Javasolt stack:

- **Frontend:** React + TypeScript + Tailwind CSS + Vite
- **Backend:** Python + FastAPI + HTTPX
- **Adatbázis:** SQLite
- **Adatforrás:** eBay Browse API, moduláris további adapterek (közös adapter-interfész: `search()`, `check_status()`)
- **Árfolyam:** Európai Központi Bank napi referencia-árfolyama (ingyenes), kézi felülírási lehetőséggel
- **Futtatás:** helyben a saját számítógépen; opcionálisan Docker

Az API-kulcsokat és titkokat kizárólag backend-környezetben (`.env`) tárold. A frontendbe nem kerülhetnek bele. Az eBay OAuth tokent a backend kéri le és cache-eli a lejáratáig (kb. 2 óra).

Ne használj fizetős AI API-t. A rendszer személyes használatra 0 Ft/hó költségű: az eBay Developer Program és a Browse API alapkeretben ingyenes, az ECB-árfolyam ingyenes, és minden helyben fut.

## 12. Működés internet nélkül

Mivel a backend és az SQLite helyben fut, a korábban tárolt találatok internet nélkül is megjeleníthetők; ehhez nincs szükség PWA-ra vagy service workerre. A megjelenítés **kizárólag egyértelmű „Korábban mentett / offline” jelzéssel** történhet.

Új kereséshez és az elérhetőség aktuális ellenőrzéséhez internet szükséges. Offline állapotban a régi találatokat nem szabad frissen ellenőrzött, aktív ajánlatként feltüntetni.

## 13. Technikai és hibakezelési követelmények

- Párhuzamos, de API-korlátokat tiszteletben tartó lekérdezés (korlátozott párhuzamosság, pl. max. 4 egyidejű kérés)
- Hálózati hibák, rate limit (HTTP 429) és időtúllépések kezelése, exponenciális visszalépéssel
- Napi API-hívásszám nyilvántartása
- Deduplikáció
- Hiányzó képek, árak, szállítási adatok kezelése
- EUR/HUF átváltás az ECB árfolyamával vagy kézzel állítható árfolyammal; az alkalmazott árfolyam és dátuma megjelenik a felületen
- Forrásonkénti keresési állapot
- Naplózás, de a titkos kulcsok és tokenek kitakarásával
- Kizárólag valós, ellenőrizhető találatok
- Biztonságos hitelesítési és konfigurációkezelés
- Eladói személyes adatot (felhasználónév, értékelés) az adatbázis ne tároljon (lásd 18. pont, adattárolási mentesség)
- Tesztek a szűréshez, EU-helyszűréshez, deduplikációhoz, modellfelismeréshez, árkalkulációhoz és státuszkezeléshez

Ha egy piactér lekérdezése sikertelen, az app **ne** állítsa, hogy a keresés sikeres volt az adott oldalon.

## 14. Fejlesztési sorrend

### 1. fázis – eBay MVP

Webes felület, keresési paraméterek, valós eBay Browse API-integráció a 3. pontban leírt, élesben mért stratégiával (EBAY_DE, országonkénti `itemLocationCountry`, állapot- és kategóriaszűrő, modellnevek VAGY-lekérdezésben), helyi EU-ellenőrzés, magyarországi szállítási díj, aukció/fix ár megkülönböztetés, ár- és modellfilterek, közvetlen linkek, aktív státusz ellenőrzése, API-hívásszámláló. A diagnosztikai mérések (kulcsellenőrzés, helyszűrők és országstratégia összevetése) elkészültek.

### 2. fázis – tárolás és haladó kezelés

SQLite, kedvencek, elrejtés, deduplikáció, „ÚJ” jelölés, árfrissítés, `getItems`-alapú kötegelt státuszellenőrzés, hirdetések életciklus-kezelése, modellfelismerés `localizedAspects` alapján.

### 3. fázis – magyar piacterek

Jófogás, HardverApró és Facebook Marketplace előre kitöltött keresőlinkjei. Automatikus lekérdezés csak akkor, ha az oldal feltételei ezt kifejezetten engedik.

### 4. fázis – opcionális funkciók

Időzített keresés, értesítések, telepíthető webapp (PWA), új konzolmodellek és további források.

## 15. Átadási és elfogadási feltételek

A projekt csak akkor kész, ha:

1. A **Keresés indítása** gomb valós eBay API-lekérést indít.
2. Megjeleníthetők aktív licitálós és fix áras hirdetések.
3. A termék tényleges helye EU-tagállam, ellenőrzött adattal (`itemLocation.country`).
4. A maximális ár szerinti szűrés helyes.
5. Minden megjelenített hirdetéshez valódi, működő eredeti URL tartozik.
6. A kedvencek és elrejtések újraindítás után is megmaradnak.
7. Nincsenek kitalált vagy bemutató találatok az éles keresési listában.
8. API-hiba esetén érthető hibaüzenetet ad.
9. A teljes kezelőfelület magyar nyelvű.
10. Helyben dokumentált lépésekkel elindítható.
11. Lejárt, eladott és nem ellenőrizhetően aktív hirdetés nem szerepel az aktív keresési eredmények között.
12. Egy teljes keresés 50 API-hívás alatt marad az alapbeállításokkal.

## 16. Elvárások a fejlesztővel szemben

**Ne csak dizájnt, látványtervet vagy statikus demót készíts; működő, futtatható alkalmazást.**

Hozd létre:

- Teljes frontend és backend forráskód
- Adatbázisséma és adatkezelés
- `.env.example` konfigurációs minta
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
- A tárolt, de az aktuális keresésben nem szereplő tételek státuszát a backend `getItems` hívással (20 tétel/hívás) ellenőrzi minden keresés során.
- Ha a `last_checked_at` **2 óránál régebbi**, a tétel automatikusan `UNKNOWN`, amíg újra nem ellenőrzik.
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
