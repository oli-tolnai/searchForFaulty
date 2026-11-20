# UI-terv (2026. november) – a Flutter-felület tervrajza

A felhasználóval egyeztetett, jóváhagyott képernyőterv. A `*.dc.html` fájlok a tervezővászon forrásai: böngészőben nem jelennek meg önmagukban (egy külön futtatókörnyezet kell hozzájuk), de a markup és az inline stílusok pontosan mutatják a felépítést, a méreteket és a színeket. A hirdetések a tervben csak példák.

## Alapelvek

- **Kevesebb elem egyszerre.** Elsőre csak a kategória, a keresőmező, a Szűrők gomb, egy egysoros összesítő a Keresés gombbal és a találatok látszanak. Minden más lenyitható vagy a részletes nézetben van.
- **Kompakt kártyák**, a részletek egy külön nézetben.
- **Egy fő művelet képernyőnként**, zöld kiemelőszínnel.
- **Nincs vízszintesen görgetendő kategóriasor a telefonon** (a felhasználó kifejezetten kérte). Helyette kategóriaválasztó a fejlécben.

## Design tokenek

| Token | Érték |
|---|---|
| Háttér | `#0F1115` |
| Felület (kártya, mező) | `#171A21`, keret `#232833` / `#262B35` |
| Emelt felület (panel, navigáció) | `#12151B`, keret `#222731` |
| Szöveg | `#E8EAED`; másodlagos `#C9CED6`; halvány `#9AA3AF` |
| Kiemelőszín | `#A8E063`, rajta szöveg `#11160B`; kiválasztott chip: háttér `#2C3B1A`, keret `#A8E063`, szöveg `#D7F5B5` |
| Aukció jelölés | háttér `#3A2F14`, szöveg `#F2C35B` |
| Fix ár jelölés | háttér `#16304A`, szöveg `#8CC4FF` |
| ÚJ jelölés | háttér `#2C3B1A`, szöveg `#B8EC7E` |
| Semleges jelölés | háttér `#252A33`, szöveg `#C9CED6` |
| Figyelmeztető sáv | háttér `#2E2614`, keret `#5A4718`, szöveg `#F5DFA8`, gomb `#F2C35B` |
| Betűtípus | Inter (400/500/600/700) |
| Lekerekítés | kártya 16, mező és gomb 12, chip és fül 999 (pill), panel teteje 20 |
| Érintési célterület | legalább 44 px |

Betűméretek: kategóriacím 24/700, képernyőcím 19–22/700, kártyacím 15/600, ár 19/700, törzs 14–15, meta 12–13.

## Képernyők

1. **Találatok** (`Main.dc.html`): fejléc: kategóriaválasztó gomb („Konzol 12 ▾”) és jobbra az „EUR · Ft” váltó. Keresőmező + „Szűrők” gomb (aktív szűrők számával). Aktív szűrők törölhető chipekként. Egy sor: „12 találat · frissítve 14:32” és jobbra a zöld „Keresés” gomb. Kártyalista. A lista alján egy lenyitható „Rejtett tételek (N)” sor. Alsó navigáció: Keresés, Kedvencek, Figyelés, Beállítások.
2. **Még nem kerestél** (`Ures.dc.html`): ikon, cím, egy mondat magyarázat, nagy „Keresés indítása” gomb, alatta „kb. N eBay-hívás · ma X / 5000 felhasználva”, és egy „Előbb beállítom a szűrőket” szöveges gomb.
3. **Keresés folyamatban** (`Betoltes.dc.html`): haladásjelző kártya („18 / 27 ország · eddig 7 találat”, Mégse), alatta váz-kártyák. A korábbi találatok a keresés végéig maradnak.
4. **Szűrők** (`Szurok.dc.html`): alulról felcsúszó panel. Elsőre: Modell (chipek), Ár ettől–eddig, Max. teljes ár, Hirdetéstípus (szegmentált: Mind / Aukció / Fix ár), Aukció zárása (Bármikor / 24 óra / 48 óra). „További beállítások (ország, kulcsszó, jelölések)” lenyitható. „Értesítés ilyen találatokról” szöveges gomb. Alul: „Törlés” és a fő gomb „N találat mutatása” (élőben számolt).
5. **Hirdetés részletei** (`Reszletek.dc.html`): kártyára koppintva nyílik (telefonon teljes képernyő, vissza gombbal). Kép, jelölések, cím, árbontás (licit/ár, szállítás, kiemelt teljes ár), adatok (modell, hely, zárás, utoljára ellenőrizve), lenyitható „Leírás és az eladó megjegyzése” (a Google Fordító gombbal). Alul: Kedvenc, Figyelés, Elrejtés, és a fő gomb „Megnyitás az eBay-en”.
6. **Elavult eredmény és rejtett tételek** (`Elavult.dc.html`): sárga sáv „3 órája frissítve – az árak és állapotok nem ellenőrzöttek” + Frissítés gomb; a kártyák halványítva „Nem ellenőrzött” felirattal. A lenyitott „Rejtett tételek” doboz csoportonként egy sor darabszámmal és nyíllal.
7. **Asztali nézet** (`Asztali.dc.html`): bal oldali NavigationRail; felül a kategóriafülek egy sorban (asztalon elférnek, nem kell görgetni); bal oldalon állandó szűrőpanel (272 px); jobbra keresőmező, rendezés, „Keresés · kb. N hívás” gomb, összesítő sor, és 4 oszlopos kártyarács (képpel felül).
8. **Kategóriaválasztó** (`Kategoria.dc.html`): alulról felcsúszó panel „Mit keresel?” címmel. Egy sor kategóriánként: ikon, név, alcím (pl. „PS5 · Xbox Series · frissítve 14:32”, „frissítve tegnap · nem ellenőrzött”, „Még nem kerestél”), jobbra a találatszám. Az aktuális kiemelve. Első sor: „Összes kategória”. Alul: „Kategóriák megjelenítése…” (melyik látszódjon).

## Kártya (telefon)

76×76 kép balra (hiba esetén semleges ikon); jobbra: legfeljebb 2 jelölés (pl. „Aukció · 32 p”, „ÚJ”, „Korai licit”, „Fix ár”), cím (max. 2 sor), „modell · ország”, egy sorban a teljes ár (vagy ha nem ismert, az ár „+ szállítás nem ismert” jelzéssel) és jobbra halványan a bontás („licit 119 € + 4,95 €”). Jobb szélen szív ikon (44×44). A többi jelölés (banned, iCloud, csomag stb.) és adat a részletes nézetben.
