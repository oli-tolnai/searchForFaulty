# Console Deal Finder · Flutter

Sötét témájú eBay-kereső Androidra és Windowsra. A kereséshez a telepített Apps Script webapp és az ahhoz beállított kliens-token szükséges.

## Futtatás Windowson

Telepítsd a Flutter SDK-t és a Visual Studióban a **Desktop development with C++** munkaterhelést. A `flutter doctor -v` megmutatja, ha hiányzik valamelyik összetevő. [Windowsos Flutter-fejlesztés](https://docs.flutter.dev/platform-integration/windows/setup)

A repó gyökeréből, PowerShellben:

```powershell
cd flutter_app
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

A `flutter build windows` a `build\windows\x64\runner\Release\` mappába készíti a futtatható csomagot x64-es Windowson. A `flutter_app.exe` mellett a mappa többi fájlja is szükséges.

## APK készítése és telepítése Xiaomi telefonra

Az APK fordításához telepítsd az Android SDK-t, és ellenőrizd az Android eszközláncot a `flutter doctor -v` paranccsal. Ezután a `flutter_app` mappában:

```powershell
flutter build apk --release
```

1. Másold a `build\app\outputs\flutter-apk\app-release.apk` fájlt a telefonra, például USB-n a **Letöltések** mappába.
2. Nyisd meg a fájlt a telefon fájlkezelőjében. Ha a rendszer kéri, engedélyezd az **Ismeretlen alkalmazások telepítése** beállítást ehhez a fájlkezelőhöz, majd térj vissza és válaszd a **Telepítés** gombot. A menü neve eltérhet a MIUI vagy a HyperOS verziójától. [Xiaomi telepítési útmutató](https://www.mi.com/pk/support/faq/details/KA-06974/)
3. Indítsd el a **Console Deal Finder** alkalmazást.

Az Android-build legalább API 23-at igényel. A release APK a gép helyi debug kulcsával van aláírva a saját célú telepítéshez. A meglévő telepítés frissítéséhez ugyanazzal az aláírókulccsal készítsd a következő APK-t. [Android APK készítése](https://docs.flutter.dev/deployment/android#build-an-apk)

## Első beállítás és keresés

1. A **Beállítások** oldalon add meg a telepített Apps Script webapp `/exec` végű címét és a hozzá tartozó **kliens-tokent**. A webapp felállításának lépései az [Apps Script útmutatójában](../apps_script/README.md) vannak.
2. Kattints a **Kapcsolat tesztelése** gombra. Siker esetén válaszd a **Mentés** gombot, majd a keresőképernyőn a **Keresés indítása** gombot.
3. A modell-, ár- és egyéb szűrők a letöltött eredményeket rendezik és szűrik. A részletes nézetben a **Leírás és az eladó megjegyzése** sor külön lekéri a hirdetés szövegét.

A cím és a token az eszköz biztonságos tárolójában marad. Az utolsó teljesen sikeres keresés helyi másolata internet nélkül is megjelenik, az eredeti frissítési idővel. Két órától a kártya „Nem ellenőrzött” jelölést kap, hat órától a régi tétel nem jelenik meg.

## Kedvencek, elrejtés és szinkron

A két eszközön ugyanazt a webapp-címet használd. A szív ikon menti a kedvencet, az **Elrejtés** eltávolítja a tételt a találatokból. Öt másodpercig visszavonhatod az elrejtést, később az **Elrejtett** oldalon állíthatod vissza. A szűrők, a rendezés, a kedvencek és az elrejtések szinkronizálódnak. A helyben sorba tett módosítások és az utolsó szinkron állapota a **Beállítások** oldalon látszik.

A kedvencek frissítése a lap megnyitásakor és a keresés után indulhat, legfeljebb 15 percenként. A lejárt kedvencek a lista végén maradnak. Az **ÚJ** címkét a hirdetés megnyitása vagy a következő keresés törli az aktuális eszközön.

## Helyi értesítések Xiaomi telefonon

1. Telepítsd a friss APK-t, és nyisd meg az alkalmazást.
2. Az első indításkor az **Értesítések engedélyezése → Tovább** után válaszd az Android **Engedélyezés** gombját. Ha korábban kihagytad, nyisd meg az app **Beállítások → Alkalmazás rendszerbeállításai → Értesítések** menüjét, és ott engedélyezd őket.
3. A telefon **Beállítások → Alkalmazások → Engedélyek → Automatikus indítás** vagy **Háttérbeli automatikus indítás** menüjében engedélyezd a **Console Deal Finder** alkalmazást.
4. A **Beállítások → Alkalmazások → Alkalmazások kezelése → Console Deal Finder → Akkumulátorkímélő** menüben válaszd a **Nincs korlátozás** lehetőséget. Az appból az **Alkalmazás rendszerbeállításai** gombbal közvetlenül megnyithatod az alkalmazás adatlapját. A menük elnevezése MIUI- és HyperOS-verziónként eltérhet.
5. Az alkalmazás **Beállítások** lapján kapcsold be az **Értesítések** kapcsolót, majd válaszd a **Próbaértesítés** gombot. Itt látható az utolsó sikeres értesítés-lekérés időpontja is.

Az Android hálózat mellett nagyjából 15 percenként ad lehetőséget a háttérben történő lekérésére. Az ütemezés késhet. Windowson az alkalmazás indításkor és futás közben ötpercenként ellenőrzi a sort. [A WorkManager időzítéséről](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work)

## Csoportfülek és helyi szűrők

A Keresés oldalon az Összes, Konzol, Kontroller, Switch, Steam Deck, iPhone és Videokártya fülek külön eredménylistát és frissítési időt tartanak. A **Keresés** csak az adott csoportot frissíti. Az **Összes kijelölt frissítése** sorban frissíti a kijelölt csoportokat; 150 feletti vagy ismeretlen költségnél megerősítést kér. A becslés a szerver ország- és lekérdezés-konfigurációjából jön; lapozás és újrapróbálás többletet jelenthet.

A **Szűrők** telefonon alsó panelt, széles ablakban oldalsó panelt nyit. A beállítások csoportonként külön szinkronizálódnak, és azonnal hatnak a letöltött listára, eBay-hívás nélkül. Az aktív feltételek chipenként eltávolíthatók. Az **Értesítés ilyen találatokról** szerkeszthető szabályt készít elő az aktuális csoport szűrőiből. Az árak bevitele a kiválasztott pénznemben történik, tárolásuk EUR.

Az összesítő részletei lenyithatók; a lista alján a **Rejtett tételek** sávból nyílnak a külön csoportnézetek. A látható fülek a Beállításokban választhatók ki és szinkronizálódnak. Telefonon alsó navigáció, széles ablakban oldalsó navigáció látható.

A helyi gyorsítótár csoportonként megmarad újraindítás után is, részleges eredménynél a hibajelzésekkel együtt. Egy másik csoport keresése nem írja felül. Két óra után figyelmeztetés és „Nem ellenőrzött” jelölés látszik; hat óra után a régi hirdetési adatok kikerülnek, de az utolsó keresés időpontja megmarad. Sikertelen frissítés nem törli a korábbi listát.

## A jóváhagyott UI-terv szerinti felület

Telefonon a fejléc kategóriaválasztója nyitja a **Mit keresel?** panelt; nincs vízszintes kategóriasor. A négy alsó pont: Keresés, Kedvencek, Figyelés, Beállítások. Az **Elrejtett hirdetések** a Beállításokból érhető el. Kártyára koppintva nyílik a részletes nézet, benne az eBay-, leírás-, figyelés- és elrejtésműveletekkel; a kártyán csak a szív marad.

Asztalon a kategóriafülek és a 272 px-es szűrőpanel állandók, 1440 px-en négy oszlopban látszanak a kártyák. A részletek párbeszédablakban nyílnak. A szűrőpanel további beállításai alatt találhatók az országok, kulcsszavak, jelölések és a rendezés. A keresés országonkénti állapota, az API-felhasználás és az Összes kategória frissítési kijelölése a **Keresés részletei** alatt maradt.

A **Mégse** a választ kliensoldalon dobja el; a már elküldött szerverkérést nem tudja leállítani. Az Inter beágyazott betűtípus, offline működik; licence az `assets/fonts/OFL.txt` fájlban van. Új csomagfüggőség nincs.

A pontos méretű képek, az éles próba és a tervtől való eltérések: [UI-ellenőrzés](../docs/ui_terv/kepernyokepek/README.md).

A képek újragenerálása csak friss, valódi keresési gyorsítótárral (a `flutter_app` mappából):

```powershell
flutter test tools/capture_ui.dart --dart-define="CDF_CAPTURE_FILE=$env:APPDATA/hu.consoledealfinder/Console Deal Finder/last-search.json"
```

Ez a kézi eszköz nem része az automatikus tesztfutásnak. Nem hívja az eBay keresési API-ját, nem gyárt hirdetést, és nem írja át a mentett felhasználói állapotot.


### Keresés más piactereken

A „Keress máshol is” blokk telefonon a találati lista végén, asztalon a szűrőpanel alján érhető el, keresés előtt is. A kiválasztott kategória első kijelölt modelljéből (enélkül a kategória általános keresőszavából) és a „hibás” szóból készít keresőlinket. Az Összes nézetben a szűrőpanelhez kiválasztott kategóriát használja. A link a rendszerböngészőben nyílik; az alkalmazás nem kérdezi le és nem olvassa ezeket az oldalakat.

A Jófogás és HardverApró formátuma a `lib/external_search.dart` fájl `externalSearchFormats` konstansában, a keresési paraméter neve az `ExternalMarket` felsorolásban javítható. A megadott nyilvános URL-formátumokat **a felhasználónak kattintással kell ellenőriznie**, hogy a megfelelő, előre kitöltött találati oldal nyílik-e meg. Automatikus ellenőrzés vagy scraping nem történt.

Ha a webapp nem ad hívásbecslést, a kliens a csoportonként ismert 2 / 4 / 1 / 1 / 7 / 2 lekérdezést szorozza 27 országgal. Ez „kb.” érték: a kiegészítő keresések, lapozás és újrapróbálás növelhetik a tényleges hívásszámot.
