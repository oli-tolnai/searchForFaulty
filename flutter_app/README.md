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
3. A modell-, ár- és egyéb szűrők a letöltött eredményeket rendezik és szűrik. A kártyán a **Leírás** gomb külön lekéri a hirdetés szövegét.

A cím és a token az eszköz biztonságos tárolójában marad. Az utolsó teljesen sikeres keresés helyi másolata internet nélkül is megjelenik, az eredeti frissítési idővel. Két órától a kártya „Nem ellenőrzött” jelölést kap, hat órától a régi tétel nem jelenik meg.

## Kedvencek, elrejtés és szinkron

A két eszközön ugyanazt a webapp-címet használd. A szív ikon menti a kedvencet, az **Elrejtés** eltávolítja a tételt a találatokból. Öt másodpercig visszavonhatod az elrejtést, később az **Elrejtett** oldalon állíthatod vissza. A szűrők, a rendezés, a kedvencek és az elrejtések szinkronizálódnak. A helyben sorba tett módosítások és az utolsó szinkron állapota a **Beállítások** oldalon látszik.

A kedvencek frissítése a lap megnyitásakor és a keresés után indulhat, legfeljebb 15 percenként. A lejárt kedvencek a lista végén maradnak. Az **ÚJ** címkét a hirdetés megnyitása vagy a következő keresés törli az aktuális eszközön.
