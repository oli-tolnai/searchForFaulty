# Console Deal Finder – 17 részes fejlesztési terv

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

A rendszer felépítése tegye lehetővé további modellek hozzáadását, például Nintendo Switch, Switch OLED és Steam Deck.

## 3. Hirdetési források

### eBay – elsődleges adatforrás

Az első teljesen működő integráció az eBay legyen, lehetőleg a hivatalos **eBay Browse API** segítségével, a hozzáférési jogosultságok és API-korlátok figyelembevételével.

Keresési célpiacok: Németország, Ausztria, Franciaország, Olaszország, Spanyolország, Hollandia, Belgium, Lengyelország, Írország. A tényleges elérhető piactér/API-támogatást a fejlesztés során ellenőrizni kell; nem minden felsorolt ország rendelkezik feltétlenül külön, azonos módon támogatott eBay marketplace-azonosítóval.

**Csak EU-tagállamban fizikailag található termékeket engedj be.** Ne keverd össze az eladó országát, a piactér országát és a termék tényleges feladási helyét. Egyesült Királyság, Svájc, USA és minden más EU-n kívüli hely kizárandó.

Támogatandó hirdetési típusok:

- Fix ár (Buy It Now)
- Licitálós aukció
- Ajánlattétel (Best Offer), ahol az adatforrás jelzi

Kezelendő mezők: aktuális ár vagy licit, licitszám (ha elérhető), aukció vége, hirdetés URL-je, azonosítója, termék helye, szállítási díj és elérhetőség. Ellenőrizni kell, hogy az adott API-hozzáférés minden szükséges aukciós adatot biztosít-e; ha nem, az app jelezze a korlátot, ne találjon ki értéket.

A magyarországi szállíthatóságot és a szállítási díjat, amennyiben hozzáférhető, ellenőrizze. Ha nem ellenőrizhető: **„Nem ismert”**. Ne legyen a nulla szállítási díj az alapértelmezés.

### Jófogás és HardverApró

Keressen „hibás”, „javításra”, „alkatrésznek” stb. megjelölésű konzolokat. Minden forráshoz külön adapter készüljön, amely az oldal hozzáférési és felhasználási feltételeit tiszteletben tartja. Ha automatikus lekérdezés nem érhető el szabályosan vagy megbízhatóan, jelenjen meg előre kitöltött, megnyitható keresőlink.

### Facebook Marketplace

Opcionális, későbbi integráció. Csak engedélyezett és megbízható hozzáférési módszerekkel működjön; ne kerüljön meg bejelentkezési, CAPTCHA- vagy hozzáférés-korlátozásokat.

**Prioritás:** a Jófogás, HardverApró és Marketplace ne blokkolja a működő eBay MVP elkészítését.

## 4. Keresés

A főoldalon legyen jól látható **„Keresés indítása”** gomb. A keresés a bekapcsolt adatforrásokból új, valós adatokat kérdezzen le.

Szűrők:

- Konzolmodellek, többes kijelöléssel
- Maximális vételár
- Maximális teljes ár szállítással együtt
- Pénznem: EUR / HUF
- Piacterek be-/kikapcsolása
- Országok
- Aukció / fix ár / mindkettő
- Keresési kulcsszavak szerkesztése

A beállítások maradjanak meg a következő megnyitásra (pl. böngészőben vagy helyi adatbázisban).

## 5. Keresési kulcsszavak

**Angol:** faulty, broken, for parts, spares or repair, not working, no display, no power, overheating.

**Német:** defekt, bastler, ersatzteile, reparatur, startet nicht, kein bild, überhitzt, geht nicht an.

**Magyar:** hibás, javításra, alkatrésznek, nem kapcsol be, nincs kép, túlmelegszik, nem működik.

A francia, olasz, spanyol és lengyel kifejezések is legyenek konfigurálhatók.

Ne egyetlen túl hosszú lekérdezésre épüljön a keresés: futtass több célzott lekérdezést, majd egyesítsd és deduplikáld az eredményeket.

Zárja ki az egyértelműen önálló kiegészítőket (kontroller, burkolat, doboz, kábel), de **ne** zárja ki a „console for parts” megfogalmazású, teljes hibás konzolokat. Bizonytalan termékazonosításnál inkább jelölje a találatot ellenőrzendőnek, mintsem tévesen teljes konzolnak minősítse.

## 6. Találati lista

Minden hirdetésnél látható:

- Termékkép
- Hirdetés címe
- Konzolmodell
- Forrás / piactér
- Vételár vagy aktuális licit
- Szállítási költség (vagy „Nem ismert”)
- Teljes ár, csak ha kiszámítható
- Ország / termék helye
- Aukció vagy fix ár
- Licitek száma, ha elérhető
- Aukció lejárata, ha releváns
- Rövid hibaleírás / leírásrészlet
- Utolsó sikeres elérhetőség-ellenőrzés időpontja
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

Az ismeretlen szállítású hirdetéseket teljes ár szerinti rendezésnél külön, egyértelműen kell kezelni; ne tekintsd a szállítást ingyenesnek.

## 8. Kedvencek és elrejtett hirdetések

Minden hirdetésnél:

- **Kedvencekhez adás** – mentés saját listába
- **Elrejtés** – ne jelenjen meg a normál eredmények között, de visszaállítható legyen

Legyen külön **Kedvencek** és **Elrejtett hirdetések** oldal. A mentések alkalmazás-újraindítás után is maradjanak meg.

A duplikáció kezelése az eredeti forrás + hirdetésazonosító alapján történjen, hogy ugyanaz a tétel több kulcsszavas keresésből ne szerepeljen többször.

## 9. Új hirdetések jelölése

Az első sikeres lekérdezéskor tárold a találatok azonosítóit. Későbbi keresésnél az addig nem látott hirdetések kapjanak **„ÚJ”** jelölést.

Aukciós árak változásakor frissüljön az aktuális licit. A már látott hirdetések ne kapjanak automatikusan új címkét pusztán árfrissítés miatt.

A találatok elérhetőségét időnként ellenőrizni kell, hogy az eladott, törölt vagy lejárt tételek ne maradjanak az aktív listában (részletesen a 17. pontban).

## 10. Felhasználói felület

Modern, letisztult, **sötét témájú**, magyar nyelvű, mobilon és asztali gépen is használható felület.

Főoldali elemek:

1. Felső navigáció
2. Szűrők és keresési beállítások
3. Kiemelt **Keresés indítása** gomb
4. Találatok száma
5. Kártyás vagy táblázatos eredménylista
6. Lapozás vagy „Továbbiak betöltése”

A keresés közben jelenjen meg a folyamat állapota és a forrásonkénti siker/hiba, hogy egy részlegesen sikeres futás ne tűnjön teljesnek.

## 11. Technológia

Javasolt stack:

- **Frontend:** React + TypeScript + Tailwind CSS + Vite
- **Backend:** Python + FastAPI + HTTPX
- **Adatbázis:** SQLite
- **Adatforrás:** eBay Browse API, moduláris további adapterek
- **Futtatás:** elsőként helyben a saját számítógépen; opcionálisan Docker

Az API-kulcsokat és titkokat kizárólag backend-környezetben tárold. A frontendbe nem kerülhetnek bele.

Ne használj fizetős AI API-t. Olyan architektúrát válassz, amely személyes használatra lehetőleg 0 Ft/hó költségű. Az eBay developer hozzáférés és a használati feltételek aktuális állapotát ellenőrizd.

## 12. Működés internet nélkül

Az alkalmazás internet nélkül is meg tudja jeleníteni a korábban tárolt találatokat, **de kizárólag egyértelműen „korábban mentett / offline” jelzéssel**.

Új kereséshez és az elérhetőség aktuális ellenőrzéséhez internet szükséges. Offline állapotban a régi találatokat nem szabad frissen ellenőrzött, aktív ajánlatként feltüntetni.

## 13. Technikai és hibakezelési követelmények

- Párhuzamos, de API-korlátokat tiszteletben tartó lekérdezés
- Hálózati hibák, rate limit és időtúllépések kezelése
- Deduplikáció
- Hiányzó képek, árak, szállítási adatok kezelése
- EUR/HUF átváltás megbízható árfolyamforrással vagy kézzel állítható árfolyammal; az alkalmazott árfolyam megjelenítésével
- Forrásonkénti keresési állapot
- Naplózás, de a titkos kulcsok kitakarásával
- Kizárólag valós, ellenőrizhető találatok
- Biztonságos hitelesítési és konfigurációkezelés
- Tesztek a szűréshez, deduplikációhoz, árkalkulációhoz és státuszkezeléshez

Ha egy piactér lekérdezése sikertelen, az app **ne** állítsa, hogy a keresés sikeres volt az adott oldalon.

## 14. Fejlesztési sorrend

### 1. fázis – eBay MVP

Webes felület, keresési paraméterek, valós eBay API-integráció, EU-s termékhely-szűrés, aukció/fix ár megkülönböztetés, ár- és modellfilterek, közvetlen linkek, aktív státusz ellenőrzése.

### 2. fázis – tárolás és haladó kezelés

SQLite, kedvencek, elrejtés, deduplikáció, „ÚJ” jelölés, árfrissítés, hirdetések életciklus-kezelése.

### 3. fázis – magyar piacterek

Jófogás és HardverApró szabályosan elérhető lekérdezési megoldásokkal; ha ez nem megvalósítható, helyette hivatalos keresőlinkek.

### 4. fázis – opcionális funkciók

Időzített keresés, értesítések, telepíthető webapp (PWA), új konzolmodellek és további források.

## 15. Átadási és elfogadási feltételek

A projekt csak akkor kész, ha:

1. A **Keresés indítása** gomb valós eBay API-lekérést indít.
2. Megjeleníthetők aktív licitálós és fix áras hirdetések.
3. A termék tényleges helye EU-tagállam, ellenőrzött adattal.
4. A maximális ár szerinti szűrés helyes.
5. Minden megjelenített hirdetéshez valódi, működő eredeti URL tartozik.
6. A kedvencek és elrejtések újraindítás után is megmaradnak.
7. Nincsenek kitalált vagy bemutató találatok az éles keresési listában.
8. API-hiba esetén érthető hibaüzenetet ad.
9. A teljes kezelőfelület magyar nyelvű.
10. Helyben dokumentált lépésekkel elindítható.
11. Lejárt, eladott és nem ellenőrizhetően aktív hirdetés nem szerepel az aktív keresési eredmények között.

## 16. Elvárások a fejlesztő AI-val szemben

**Ne csak dizájnt, látványtervet vagy statikus demót készíts; működő, futtatható alkalmazást.**

Hozd létre:

- Teljes frontend és backend forráskód
- Adatbázisséma és adatkezelés
- `.env.example` konfigurációs minta
- Függőségek / telepítőparancsok
- Automatizált tesztek
- `README.md` részletes indítási útmutatóval
- A szükséges eBay API-regisztráció és jogosultságok pontos leírása

Valós integrációt használj, ne demóadatokat. Ha valamihez nincs kulcs vagy az API nem biztosít egy kért funkciót, ezt világosan írd le, és készíts korrekt részmegoldást; ne szimuláld kész funkcionalitásként.

Fázisonként dolgozz, minden fázis végén indítsd és teszteld a rendszert. Az elsődleges cél a **működő eBay-kereső**.

## 17. Kötelező követelmény: lejárt és eladott hirdetések kizárása

**Az aktív találati listában kizárólag aktuálisan aktív, ellenőrizhetően megvásárolható vagy licitálható hirdetések jelenjenek meg.** A lejárt, eladott, lezárt, törölt vagy már nem elérhető tételek ne szerepeljenek benne.

### 17.1. eBay aukciók

- Csak aktív aukciókat mutasson.
- A lejárat legyen későbbi, mint az aktuális idő.
- A lezárt aukciókat távolítsa el az aktív listából.
- Ha egy aukció idő előtt lezárul, az állapotfrissítés után tűnjön el.
- A hátralévő időt jelenítse meg. Amikor a visszaszámláló eléri a nullát, az aukció ne maradjon aktívként látható: kerüljön ellenőrzésre, vagy ideiglenesen ki az aktív listából.

### 17.2. Fix áras hirdetések

- Ellenőrizze az aktuális megvásárolhatóságot és készletet, amennyiben az adatforrás jelzi.
- A „Sold”, „Out of stock”, „Ended”, „Nicht mehr verfügbar” és az ezekkel egyenértékű státuszokat zárja ki.
- Többdarabos hirdetés csak pozitív, elérhető készlet mellett maradjon aktív, ha a piactér ezt az adatot szolgáltatja.

### 17.3. Jófogás és HardverApró

- Az eladott, törölt, archivált és inaktív hirdetések ne jelenjenek meg.
- Ha a forrásból az aktuális státusz nem ellenőrizhető, ne mutassa a hirdetést biztosan aktívként.

### 17.4. Elérhetőségi státuszok és frissesség

Tárolandó mezők:

- `status`: `ACTIVE`, `ENDED`, `UNKNOWN`
- `last_checked_at`: az utolsó állapotellenőrzés időpontja
- `source`, `source_listing_id`, `listing_url`
- `end_time`, ahol van
- Az esetleges állapotellenőrzési hiba és annak ideje

A normál aktív találati listába **csak `ACTIVE`** státusz kerülhet.

Minden új keresés alkalmával frissítse az elérhetőségi állapotot ott, ahol lehetséges. API-hiba, időtúllépés, ismeretlen státusz vagy elavult ellenőrzés esetén a hirdetés ne kapjon megalapozatlan `ACTIVE` besorolást.

Külön „Nem ellenőrizhető” vagy archív nézet készülhet, de az elemek ott egyértelműen legyenek elkülönítve az aktív ajánlatoktól.

### 17.5. Újrahirdetés és státuszváltozás

Ha ugyanazt a konzolt az eladó új hirdetésazonosítóval ismét meghirdeti, megjelenhet új találatként. Ha egy korábban mentett hirdetés időközben lejárt, ne maradjon bent a fő keresési listában.

### 17.6. Elfogadási tesztek

- Lejárt aukció nem jelenhet meg az aktív találatok között.
- Eladott fix áras hirdetés nem jelenhet meg.
- Törölt hirdetés nem jelenhet meg.
- Ismeretlen állapotú hirdetés nem jelenhet meg aktívként.
- A korábban eltárolt, később lezárt hirdetés eltűnik az aktív listából.
- A keresési futás friss státuszt ellenőriz, amennyiben az API lehetővé teszi.
- A hirdetésnél látszik: **„Utoljára ellenőrizve: …”**.

**Fontos megkötés:** 100%-os, másodpercre pontos elérhetőség nem garantálható, mert egy hirdetést az ellenőrzés után is megvehetnek. A rendszer törekedjen a legfrissebb állapotra, és a bizonytalanságot mindig jelezze.
