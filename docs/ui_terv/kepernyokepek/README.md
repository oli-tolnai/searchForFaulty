# A jóváhagyott UI-terv Flutter-megvalósítása – 2026-11-20

A képek a tényleges Flutter-képernyőkből készültek, pontosan **390×844** és **1440×900** logikai pixelben, 1-es pixelsűrűséggel, a `flutter_app/tools/capture_ui.dart` kézi renderelővel. Nem a HTML-vázlatokat fényképezik, és nem tartalmaznak kitalált hirdetést. A Windows-alkalmazást külön, natívan is elindítottam és éles kereséssel ellenőriztem. Android-készüléken ebben a feladatban nem teszteltem.

## Képek

| Állapot | Telefon | Asztal |
|---|---|---|
| Találatok | [Main](Main_390x844.png) | [Main](Main_1440x900.png) |
| Kategóriaválasztó | [Kategória](Kategoria_390x844.png) | A felső kategóriafülek helyettesítik. |
| Üres kategória | [Üres](Ures_390x844.png) | [Üres](Ures_1440x900.png) |
| Betöltés | [Betöltés](Betoltes_390x844.png) | [Betöltés](Betoltes_1440x900.png) |
| Szűrők | [Szűrőpanel](Szurok_390x844.png) | [Állandó szűrőpanel](Szurok_1440x900.png) |
| Hirdetés részletei | [Teljes képernyő](Reszletek_390x844.png) | [Párbeszédablak](Reszletek_1440x900.png) |
| Elavult eredmény | [Elavult](Elavult_390x844.png) | [Elavult](Elavult_1440x900.png) |
| Rejtett csoportok | [Rejtett](Rejtett_390x844.png) | [Rejtett](Rejtett_1440x900.png) |
| Asztali összkép | A telefonos Main nézet. | [Asztali](Asztali_1440x900.png) |

## Adatok és ellenőrzés

Az éles Windows-próba konzolkeresése sikeres volt: **56 API-hívás, 133 normalizált tétel**. Az eszköz meglévő, tiltott tételeket kizáró szűrőjével 11 alaplistás és 121 rejtett tétel látszott; a kézi renderelés alapértelmezett szűrőivel 12 alaplistás tétel. A backend besorolása és szűrési szabályai változatlanok; a képen is látható, konzolkeresésből érkezett ellenőrzendő kontroller ezért nem lett átminősítve.

A képek a friss, normalizált helyi gyorsítótárból készültek, eladói adat nélkül. A képek és hirdetéscímek valódiak; sikertelen képbetöltésnél a semleges helykitöltő jelenik meg. A pontos méretű PNG-k Flutter-renderelések, nem fizikai telefon képernyőmentései.

A **betöltés** képén a renderelő függőben tartja a keresési Future-t, valódi korábbi találatok mellett. Az **elavult** és rejtett-csoport képeknél kizárólag a renderelő órája lép a tényleges keresés időpontja után három órára. Nem változtatja meg a hirdetések időbélyegét, árát vagy az éles app óráját. Így ellenőrizhető a sárga sáv, a halványítás és a „Nem ellenőrzött” felirat várakozás és becsült hirdetési adat nélkül. A kézi renderelő nem módosítja a felhasználó mentett szűrőit vagy szerveroldali állapotát.

## Megvalósítási döntések és eltérések

- **Inter beágyazva:** az eredeti Inter projekt változó TTF-je, SIL Open Font License alatt (`flutter_app/assets/fonts/OFL.txt`). Offline is működik; nincs új futásidejű függőség vagy Google Fonts-hálózati kérés. A színek központi `Ui` tokenekből származnak.
- **Asztali részletek:** párbeszédablak, hogy a négysávos rács a háttérben megőrizze szélességét és görgetési helyét.
- **Haladás:** a változatlan webapp csak a teljes választ adja vissza. Ezért nincs kitalált „X / 27 ország” számláló: általános állapotjelző és magyarázat látszik. A korábbi találatok a teljes keresési ciklus végéig láthatók.
- **Mégse:** kliensoldali megszakítás, a később visszaérkező választ nem veszi át. A már elküldött szerverkérést nem tudja leállítani, annak hívásai elfogyhatnak; a felület ezt jelzi, és a folyamat végéig nem indít új párhuzamos keresést.
- **Hívásbecslés:** a telepített webappból a próba során nem állt rendelkezésre használható konfigurációs becslés. A gomb ezért őszintén „becslés nincs” feliratot mutat; nem került beégetett szám vagy backend-módosítás a feladatba.
- **Megőrzött vezérlők:** rendezés telefonon a „További beállítások” alatt és a lista alján; API-hívások, árfolyam, országonkénti hibák/warnings, az Összes kategória frissítési kijelölése a lenyitható „Keresés részletei” alatt. Az Összes nézet szűrőpaneljén külön kiválasztható, mely kategória saját szűrőit módosítjuk.
- **Aukciózárás:** a korábbi 6 és 12 órás értékek is megmaradtak a 24/48 óra mellett, hogy a szinkronizált szűrők ne veszítsenek információt.
- **Érintési célok:** legalább 44 px; emiatt néhány, a rajzon 30–38 px magas vezérlő nagyobb. A modellcsipek teljes, meglévő modellneveket használnak.
- **További funkciók:** kedvencek, figyelés és szabályok a meglévő képernyőiken, az új központi témával; az Elrejtett hirdetések a Beállításokból érhetők el. Az értesítési háttérfolyamat, szinkron és adattárolási szabályok nem változtak.

## Ellenőrzések

`flutter analyze`, 57 Flutter-teszt, 630 Apps Script-teszt és Apps Script lint sikeres. A meglévő tesztek az új elérési utakat használják: a korábbi átváltási, szállítási, rejtési, figyelési, gyorsítótár- és lejárati elvárások megmaradtak. Új teszt ellenőrzi a kategóriapanelt, az élő szűrőszámot, a részletnézetet, a 272 px-es panelt és négysávos rácsot, valamint a megszakított keresés késői válaszának eldobását.

A backend változatlan, nincs szükség clasp push-ra vagy új webapp-verzióra. A friss Windows- és APK-build a szokásos `flutter_app/build/` helyen található, nem kerül gitbe.
