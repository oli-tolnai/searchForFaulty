# Új eszközcsoportok – a 2026-11-17-i címek értelmezése

A 291 eredeti példát a `new_device_titles_live_2026-11-17.json` őrzi változatlanul. A `diagnostic` mező nem elvárás. Az alkalmazás tesztelvárásai külön, címhez és forrássorszámhoz kötve a `new_device_titles_expected.json` fájlban vannak. A régi konzolos és kontrolleres besorolások tesztelvárásai változatlanok.

A cím alapján nem teljesen eldönthető eseteknél ezek a döntések születtek:

| Cím | Döntés és bizonytalanság |
|---|---|
| Nintendo Switch Oled Original Ersatzteile | Konzol, Switch OLED. Az „Ersatzteile” állapotjelző; önálló alkatrész nincs megnevezve. A leírásból derülhet ki, hogy valóban teljes készülék. |
| Steam Deck - kaputter Lautsprecher - 256GB OVP | Konzol, Steam Deck (változat nem ismert). A tárhelyből nem állítunk biztos LCD/OLED változatot. |
| Apple iPhone 12 iCloud Gut für Ersatzteile! Defekt | Telefon, iPhone 12; iCloud-állapot ismeretlen. Az „iCloud” puszta említése nem egyértelmű zárolási állítás. |
| Apple iPhone 14 Pro 512 GB Grau iOS Smartphone – Ersatzteil/defekt mit iCloud Sp | Telefon, iPhone 14 Pro; iCloud-állapot ismeretlen. A csonkolt „Sp” részletet nem egészítjük ki „Sperre”-re. |
| Apple iPhone 13 Pro 128 GB Grau Smartphone Gesspert Ohne Simlock Defekt | iCloud-zároltként rejtett: a „Gesspert” a „gesperrt” nyilvánvaló elírásaként kezelt. Az „Ohne Simlock” ezt nem cáfolja. |
| iPhone 13 Pro, 13 Pro Max & 14 Pro Max – Geräte, Gehäuse & Ersatzteile – Bastler | Telefoncsomag, mindhárom megnevezett modell támogatott. A készülékek teljessége és darabszáma nem igazolható a címből. |
| Apple iPhone 12 Pro / iPhone 8 Konvolut | Ellenőrzendő vegyes csomag, támogatott és régi modell együtt. |
| 9 Apple iPhones + Ersatzdisplay – defekt/ungeprüft – Bastler-Konvolut | Ellenőrzendő: a kilenc készülék modellje ismeretlen, a csomagot nem tekintjük automatikusan támogatottnak. |

A régi iPhone-ok a nem támogatott modellcsoportban maradnak akkor is, ha zárat említenek; az `icloud_status=locked` megőrződik. A zármentesség jelölése kizárólag az eladó állítása. A SIM-zárról szóló szöveg nem bizonyít iCloud-mentességet.

## Keresés és szállítás

Az új csoportok kiegészítő keresésének konfigurációja üres; mérés nélkül nincs új használtállapotú lekérdezés. A fő kulcsszavak országonként: Switch 1, Steam Deck 1, iPhone 7, videokártya 2. A 27 ország első oldalai rendre 27, 27, 189, 54 hívást jelentenek, a lapozáson és újrapróbálásokon felül.

A keresés nem indít szállítási getItem-hívást. Ismert díj esetén `yes`, egyébként korábbi, hat órán belüli `yes`/`no` gyorsítótár alkalmazható; enélkül `probably_no`, rejtett csoporttal. A „Leírás” lekérése ellenőrzi és gyorsítótárazza a szállítást, valamint az iPhone zárra utaló leírását is értelmezi. Hiányzó információból nem becsül szállítási díjat.

A kliens és az új szabályszerkesztő kezdetben a korábbi Konzolok/Kontrollerek kijelölést tartja meg; a négy új csoport külön bekapcsolható. A search API explicit csoportlista nélkül mind a hatot lekéri. A régi, üres modelllistájú értesítési szabályok a két korábbi csoportnál maradnak; az új csoportok ezekhez külön hozzárendelhetők.

## Finomítás és felületi átalakítás – 2026-11-18

A fenti táblázat a korábbi döntéseket őrzi. Az új szabály felülírja az `iCloud Sp` / `iCloud Sperr` / `iCloud Gut`, illetve az elírt `Icload`, `iClod`, `Gespert`, `Gesspert` eseteket: ezek zároltra utalnak, ezért `icloud_locked`, rejtett, de megtekinthető csoportba kerülnek. Az „iCloud Gut” nem egyértelmű nyelvi bizonyíték: óvatos jelzésként kezeljük, nem igazolt műszaki tényként. A hirdetés leírása ellenőrizhető; a SIM-zár továbbra is külön fogalom.

Támogatott iPhone-okból álló csomag: `phone_bundle`; más márkával / iPaddel vegyes telefoncsomag: `not_supported_bundle` (rejtett). Csak régi modellek: `unsupported_model`. Támogatott és régi iPhone együtt, vagy modell nélküli csomag: ellenőrzendő marad.

A videokártyáknál felismerjük a gyártói előtag után álló egyértelmű 3070/3080-as modelleket, és különválasztjuk a régi, nem támogatott kártyákat, teljes asztali PC-ket, WLAN/SATA-kártyákat és a többkártyás csomagokat. Márkanévből, memóriaméretből vagy általános „GPU” szóból nem találunk ki modellt.

A korábbi éles jelentés a [rögzített mérési jelentésben](new_device_search_verification_2026-11-17.md), a géppel olvasható adatok a mellette lévő JSON-ban vannak. A címekből készített fixture újrabesorolásával (nem új éles mérés):

| Csoport | Korábbi ellenőrzendő | Új szabályokkal megmaradó |
|---|---:|---:|
| Switch | 0 | 0 |
| Steam Deck | 0 | 0 |
| iPhone | 165 | 94 |
| Videokártya | 26 | 5 |

Ez a korábban ellenőrzendő címek összehasonlítása; az aktuális kínálat és az összes tétel új élő darabszáma eltérhet. A GPU-nál megmaradó bizonytalan címek: „radeon Grafikkarte”, „sapphire radeon grafikkarte”, „GPU”, „Defekte Grafikkarte”, „asus rog strix”. Mind a 26 korábbi GPU-címhez önálló elvárt besorolás tartozik a tesztben. A régi fixture tíz elvárása az itt kért új zárolási / csomagszabály miatt változott, a tesztek nem lettek kikapcsolva.
