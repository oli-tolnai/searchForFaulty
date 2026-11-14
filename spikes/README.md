# eBay-mérés Google Apps Scriptben

1. Nyisd meg a [script.new](https://script.new/) oldalt a saját Google-fiókoddal. Az új, privát projekt alapértelmezett szerkesztőfájljába másold az [apps_script_benchmark.gs](apps_script_benchmark.gs) teljes tartalmát.
2. A fogaskeréknél nyisd meg a **Projektbeállítások** oldalt. A **Script properties** részben adj hozzá két tulajdonságot. Az `EBAY_CLIENT_ID` értéke az éles eBay App ID, az `EBAY_CLIENT_SECRET` értéke az éles Cert ID. A projektet tartsd privátban, a kulcsokat csak a tulajdonságokhoz írd be.
3. Mentsd a projektet, válaszd a `runEbayBenchmark` függvényt, és kattints a **Futtatás** gombra. Az első alkalommal engedélyezd a külső HTTP-kéréseket a saját Google-fiókoddal. Webapp-telepítésre, táblázatra és triggerre ehhez a méréshez nincs szükség.
4. A **Végrehajtási naplóból** küldd vissza a két JSON összesítőt és az esetleges futáshibát. A Google-fiók azonosítójára, a kulcsokra, tokenre és nyers API-válaszra nincs szükség.

A program egy OAuth-kéréssel indít, majd mindkét módban 54 első oldalt tervez, azonos paraméterekkel. A lapozásra módonként négy további hívást enged, legfeljebb öt oldallal ország és modellcsoport páronként. A párhuzamos mód négyes kötegeket használ. Így egy sikeres, lapozás nélküli futás 109 összes HTTP-kérést jelent, lapozással legfeljebb 117-et. A mért idők az OAuth-kérés utáni keresést és minimális válaszfeldolgozást tartalmazzák.

Ha emelkedik a hibák száma, megjelenik HTTP 429, marad el nem indított oldal vagy elfogy a lapozási keret, az időeredmény mellé ezt is jegyezd fel. Kötegszintű kivételnél a sikeres hálózati kérések pontos száma nem állapítható meg. Az összesítő az összes visszakapott sort és külön az egyedi, EU-ban található találatokat számolja. A program nem ment hirdetésadatot, és csak darabszámokat, HTTP-státuszokat és figyelmeztetési kódokat naplóz.
