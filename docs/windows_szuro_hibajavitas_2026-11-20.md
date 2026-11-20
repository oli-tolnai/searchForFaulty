# Windows-szűrőhibák vizsgálata és javítása – 2026-11-20

## Reprodukció

A változtatások előtt `flutter run -d windows` indítással, a felhasználó valódi helyi keresési gyorsítótárával reprodukáltam az Összes nézet eltérő szűrőhatását, a hibás hívásbecslést és a további beállítások kivételét. Nem indítottam új eBay-keresést. A módosítás előtti Összes nézet 107 találata a konzolos Fix ár kapcsolóval csak 98-ra csökkent, miközben a kontroller- és Switch-aukciók megmaradtak; a panel alja csak 3 konzolt számolt. A gomb közben kb. 56 hívást jelzett a hat látható kategóriára.

A telefonos elrendezést először 1000 px alá szűkített debugablakban ellenőriztem. A javítás után külön, ideiglenesen 390×844-es induló Windows-ablakkal is futott a debugalkalmazás. Az induló ablakméret mérési módosítását visszaállítottam, nem része a commitnak. A 390×900 és 1440×900 logikai méretű widgettesztek a keskeny és széles útvonalat egyaránt ellenőrzik.

## 1. Az Összes nézet saját szűrői

**Gyökérok:** a panel a `filterGroup` változóban választott csoportot szerkesztette, a lista pedig minden tételre a saját eszközcsoportjának szűrőjét alkalmazta. Emiatt a konzolos feltétel nem hathatott a kontrollerekre vagy más kategóriákra.

**Javítás:** külön `search_filter_all` szinkronizált beállítás, kizárólag közös feltételekkel; az Összes lista minden tételén ez fut. A kategóriák saját szűrői ettől függetlenek maradnak. Nincs modell- vagy kategóriaválasztó, nincs csoportspecifikus kapcsoló. A backend ezt a settings-kulcsot is validálja; a modell- és csoportspecifikus mezőket semleges alapértékre állítja. Az Összes szűrőből készülő értesítési szabály az összes látható csoportra vonatkozik.

**Tesztek:** mindkét képernyőméreten a 30 EUR felső árhatár mind a konzolos, mind a kontrolleres 80 EUR-os tételt kizárja, mindkét 20 EUR-osat megtartja. Független mentés/visszatöltés, valamint szerveroldali state_apply/state_get próba.

## 2. Az Összes hívásbecslése

**Gyökérok:** a frissítés a régi, külön `selected_groups` kijelölést használta, miközben az Összes nézet az összes látható csoport adatait mutatta. A tartalékbecslés a kiegészítő 6 lekérdezést is kihagyta.

**Javítás:** az Összes frissítés és becslés ugyanazt a látható csoportlistát használja. A becslés csoportonként a szerver értékét veszi, hiányában a helyi alapot, így hiányos konfigurációnál is összegazonos. A helyi értékek: konzol 56, kontroller 112, Switch 27, Steam Deck 27, iPhone 189, videokártya 54; összesen **kb. 465**. Ez első oldalas becslés, a lapozás/újrapróbálás további hívásokat jelenthet. A 150 feletti megerősítés ugyanezt az összeget mutatja.

**Tesztek:** összegazonosság, részleges konfiguráció, láthatóság és korábbi kijelölés eltérése, 168-as megerősítés két látható csoportra, majd tényleges kérés mindkét csoportra (mockkal).

## 3. Szürke panel és lefagyás

**Debug-kivétel:** `type 'bool' is not a subtype of type 'double?' in type cast`, a `ScrollPosition.restoreScrollOffset` alatt, egy `EditableText` építésekor. Ezt további framework-assertionök követték. Nem korlátlan magasság okozta.

**Gyökérok:** az ExpansionTile a PageStorage-ben logikai értékkel tárolta a nyitott állapotot. A benne lévő szövegmezők saját PageStorage-azonosító nélkül ugyanezt az ősi kulcsot használták a görgetési pozíció visszaolvasásához, ahol számot vártak. A külön ValueKey nem ad külön PageStorage-helyet.

**Javítás:** a mezők és a megmaradó legördülők saját PageStorageKey-t kaptak. A Rendezés kikerült a lenyitható panelből; keskeny nézetben is a lista fölött, szélesben az eszköztárban látható. A rövid felirat és a 210 px-es vezérlő megtartva.

**Tesztek:** 20 teljes nyitás–görgetés–kulcsszó-beírás–bezárás mindkét szélességen, kivétel és ErrorWidget nélkül. A javított natív széles és telefonos debugpróbában sem jelent meg új kivétel.

## 4. Fix ár és aukció

**Gyökérok:** az önálló csoportszűrőben a FIXED_PRICE ellenőrzés már helyes volt. Az Összes nézetben a többi csoportra nem jutott el a beállítás (1. hiba). Ezenkívül az AUCTION+FIXED_PRICE hirdetéseket a kártya csak „Aukció”-ként jelölte, így szabályosan benne lehettek a Fix ár listában, félreérthető felirattal. A vizsgált gyorsítótárban nem hiányzott a buying_options.

A helyi, normalizált, eladói adat nélküli gyorsítótárból kiolvasott valós példák:

- DEFEKT Nintendo Switch Lite 32GB Handheld Konsole Koralle → `["AUCTION"]`
- Xbox wireless controller - robot White-Stickdrift-LB Taste Defekt → `["AUCTION", "BEST_OFFER"]`
- Sony DualSense PS5 Wireless Controller Weiß/Schwarz kabellos/USB Trackpad → `["FIXED_PRICE", "AUCTION"]`

**Javítás:** az Összes közös típusszűrőjének alkalmazása; AUCTION+FIXED_PRICE esetén „Aukció + Azonnali vétel” címke. A régi, buying_options nélküli tétel ismeretlen típusú: kizárólag Mind alatt marad, nem kap kitalált FIXED_PRICE értéket. A BEST_OFFER önmagában nem helyettesíti a FIXED_PRICE-t. A javított natív Összes/Fix ár nézet 63 tételt mutatott, a kombinált hirdetés új címkéjével.

**Tesztek:** AUCTION, FIXED_PRICE, mindkettő, FIXED_PRICE+BEST_OFFER, AUCTION+BEST_OFFER, hiányzó mező; Mind/Aukció/Fix ár egyezés, kombinált kártyacímke.

## Befejezés

76 Flutter-teszt és flutter analyze, 643 Apps Script-teszt és lint sikeres. Windows- és release APK-build sikeres; a buildkimenet nem kerül gitbe. Új függőség nem kellett. Az Apps Script forrása clasp-pal feltöltve, de a `search_filter_all` szinkronhoz a felhasználónak új verziót kell telepítenie a meglévő webapphoz. Android fizikai készülékén nem történt próba; a telefonos felépítést Windows-debugban és widgetteszttel ellenőriztem.

A debugpéldányok a próba után leállítva. Az új Összes-szűrő szerveroldali szinkronját éles webapp-verzióval még nem ellenőriztem: ehhez a felhasználói verziótelepítés szükséges.
