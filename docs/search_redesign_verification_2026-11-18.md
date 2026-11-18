# Keresőfelület és besorolás – ellenőrzés, 2026-11-18

## Éles webapp

A felhasználó telepítette az új verziót. A `ping` visszaadja a 27-es országszámot és a csoportok becsült hívásszámát: konzol 56, kontroller 112, Switch 27, Steam Deck 27, iPhone 189, videokártya 54. A becslés az első oldalakat és a konfigurált kiegészítő kereséseket tartalmazza, a lapozást és újrapróbálást nem.

| Csoport | Állapot | Tényleges API-hívás | Összes visszaadott tétel | Ellenőrzendő |
|---|---|---:|---:|---:|
| Konzol | success | 56 | 125 | 2 |
| Kontroller | success | 113 | 499 | 1 |
| Switch | success | 27 | 154 | 0 |
| Steam Deck | success | 27 | 6 | 0 |
| iPhone | success | 197 | 2399 | 92 |
| Videokártya | success | 54 | 562 | 5 |

Összesen 474 eBay API-hívás, automatikus getItem-szállítási próbák nélkül. A szerver típusszámai és pontos ellenőrzendő darabszámai a [JSON-összesítésben](search_redesign_live_2026-11-18.json) vannak. A darabszámok a rejtett tételeket is tartalmazzák; az alaplista és az aktív szűrők ennél kevesebb kártyát mutatnak.

## Windows és telefonos méret

A valódi Windows-appból indított Switch-keresés, majd a Konzol + Kontroller frissítése sikerült. A Switch eredménye (154 tétel, ebből 54 alaplistás) a többi csoport frissítése közben és utána is megmaradt. A csoportgombon megjelent a 27-es becslés; a két eredeti csoportnál a 168 hívásos megerősítő párbeszéd. Az újraindítás és a telefonos/asztali elrendezés ellenőrzése a helyi csoportgyorsítótárral történt.

A telefonos képernyőképek a Windows-app keskeny, telefonméretű ablakából készültek, valódi eBay-eredményekkel. Ez az adaptív elrendezés ellenőrzése; a friss APK fizikai Android-készüléken való telepítését és megjelenését ebben a feladatban nem ellenőriztem. A képeken nincs beállítási cím, token vagy eladói adat.

## Automatikus ellenőrzés

- Apps Script: 630 teszt, szintaxis/lint rendben.
- Flutter: 53 teszt, `flutter analyze` hibamentes.
- Windows release és Android release APK elkészült. Az APK-fordító a meglévő WorkManager-bővítmény jövőbeli Kotlin Gradle-kompatibilitásáról figyelmeztet; a jelenlegi fordítás sikeres.
- A rögzített korábbi címhalmazon iPhone 165 → 94, GPU 26 → 5. Ez nem azonos a fent látható új éles kínálattal.

Az „iCloud Gut” óvatosságból zároltra utaló jelzés, nem bizonyított zárállapot; az indoklás és a megmaradt bizonytalan GPU-címek a [besorolási jegyzetben](uj_eszkozcsoportok_besorolas.md) szerepelnek.
