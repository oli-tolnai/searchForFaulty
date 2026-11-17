// Diagnostic only: these groups are deliberately absent from DEVICE_GROUPS.
const NEW_DEVICE_DIAGNOSTIC = {
  switch: { name: 'Switch', taxonomy: 'Nintendo Switch Konsole', queries: ['nintendo switch', 'switch oled', 'switch lite', 'switch 2'] },
  steam_deck: { name: 'Steam Deck', taxonomy: 'Steam Deck', queries: ['steam deck'] },
  iphone: { name: 'iPhone', taxonomy: 'iPhone 13', queries: ['iphone', 'iphone 11', 'iphone 12', 'iphone 13', 'iphone 14'] },
  gpu: { name: 'Videokártya', taxonomy: 'Grafikkarte RTX 3080', queries: ['rtx', 'radeon', 'rtx 30', 'rtx 40', 'rtx 50', 'rx 6', 'rx 7'] },
};

const NEW_DEVICE_CATEGORIES = {
  switch: ['V1', 'V2', 'Lite', 'OLED', 'Switch 2', 'Tartozék', 'Csomag', 'Bizonytalan'],
  steam_deck: ['LCD', 'OLED', 'Tartozék', 'Bizonytalan'],
  iphone: ['iPhone 11', 'iPhone 11 Pro', 'iPhone 11 Pro Max', 'iPhone 12', 'iPhone 12 mini', 'iPhone 12 Pro',
    'iPhone 12 Pro Max', 'iPhone 13', 'iPhone 13 mini', 'iPhone 13 Pro', 'iPhone 13 Pro Max', 'iPhone 14',
    'iPhone 14 Plus', 'iPhone 14 Pro', 'iPhone 14 Pro Max', 'Régebbi', 'Újabb', 'Alkatrész', 'Csomag', 'Bizonytalan'],
  gpu: ['RTX 20', 'RTX 30', 'RTX 40', 'RTX 50', 'GTX', 'RX 5000', 'RX 6000', 'RX 7000', 'RX 9000', 'Egyéb', 'Nem videokártya', 'Bizonytalan'],
};

function classifyNewDeviceTitle(group, title) {
  const words = diagnosticTitleWords(title);
  const result = (category, supported = false, model = category) => ({ category, model, supported, lock_mentioned: false });
  const bundle = /\b(?:[2-9]\s*x|[2-9]\s*(?:er set|stuck|pieces|pezzi)|lot|konvolut|bundle of)\b/.test(words);
  if (group === 'switch') {
    const strong = /\b(?:konsole|console|spielkonsole|handheld|tablet)\b/.test(words);
    if (/\b(?:joy ?cons?|dock(?:ing)?|ladestation|netzteil|charger|hulle|case|tasche|display|mainboard|platine)\b/.test(words) && !strong) return result('Tartozék');
    const models = [];
    if (/\b(?:switch 2|b(?:ee) 001)\b/.test(words)) models.push('Switch 2');
    if (/\b(?:he(?:g) 001|oled)\b/.test(words)) models.push('OLED');
    if (/\b(?:hdh 001|lite)\b/.test(words)) models.push('Lite');
    if (/\bhac 001 01\b|\bv2\b/.test(words)) models.push('V2');
    else if (/\bhac 001\b|\bv1\b/.test(words)) models.push('V1');
    if (bundle) return result('Csomag', models.length > 0, models.join(' / ') || 'Bizonytalan');
    return models.length === 1 ? result(models[0], true) : result('Bizonytalan');
  }
  if (group === 'steam_deck') {
    if (/\b(?:dock|docking|case|tasche|hulle|charger|netzteil|schutzglas|mainboard|display|screen)\b/.test(words) &&
        !/\b(?:konsole|console|handheld|komplett|lcd|oled)\b/.test(words)) return result('Tartozék');
    if (/\b(?:display|screen)\b/.test(words) && /\b(?:ersatz|replacement|nur|only|fur|for)\b/.test(words) &&
        !/\b(?:konsole|console|handheld|komplett)\b/.test(words)) return result('Tartozék');
    const lcd = /\blcd\b/.test(words);
    const oled = /\boled\b/.test(words);
    return lcd !== oled ? result(oled ? 'OLED' : 'LCD', true) : result('Bizonytalan');
  }
  if (group === 'iphone') {
    const locked = /\b(?:icloud|gesperrt|locked|aktivierungssperre|bloque|bloccato|bloqueado|activation lock)\b/.test(words);
    let classified;
    const part = /\b(?:display|screen|ecran|schermo|pantalla|akku|battery|batterie|backcover|ruckseite|ruckglas|back glass|hinterglas|mainboard|motherboard|platine|logic board)\b/.test(words);
    const handset = /\b(?:\d+ ?gb|komplett|smartphone|handy|telefono|telephone)\b/.test(words);
    const damage = /\b(?:display|screen|ecran|akku|battery) (?:ist |is )?(?:defekt|broken|kaputt|schaden|damage|gerissen|riss)\b/.test(words);
    if (part && !handset && !damage) classified = result('Alkatrész');
    else if (bundle) classified = result('Csomag');
    else {
      const models = [...words.matchAll(/\biphone\s*(1[1-7])(?:\s*(pro max|pro|mini|plus))?\b/g)]
        .map(match => 'iPhone ' + match[1] + (match[2] ? ' ' + (match[2] === 'mini' ? 'mini' : match[2].replace(/\b\w/g, c => c.toUpperCase())) : ''));
      const unique = [...new Set(models)];
      const old = /\biphone\s*(?:x[rs]?|[1-8]|se)\b/.test(words);
      if (unique.length !== 1 || old && unique.length) classified = result(old && !unique.length ? 'Régebbi' : 'Bizonytalan');
      else {
        const generation = Number(unique[0].match(/\d+/)[0]);
        const variantValid = !(/(?:11|14) mini|11 Plus|12 Plus|13 Plus/.test(unique[0]));
        classified = !variantValid ? result('Bizonytalan') : generation >= 15
          ? result('Újabb', false, unique[0]) : result(unique[0], true);
      }
    }
    return { ...classified, lock_mentioned: locked };
  }
  if (group === 'gpu') {
    const part = /\b(?:kuhler|cooler|heatsink|lufter|fan|ventilateur|waterblock|wasserblock|backplate|ovp|karton)\b/.test(words);
    const card = /\b(?:grafikkarte|graphics card|video card|carte graphique|scheda video)\b/.test(words);
    if (part && (!card || /\b(?:nur|only|solo|seulement|ersatz|replacement)\b/.test(words)) &&
        !/\b(?:mit|with|avec|con)\b/.test(words)) return result('Nem videokártya');
    const models = [];
    for (const [name, pattern] of [
      ['RTX 20', /\brtx\s*20\d{2}\b/], ['RTX 30', /\brtx\s*30\d{2}\b/],
      ['RTX 40', /\brtx\s*40\d{2}\b/], ['RTX 50', /\brtx\s*50\d{2}\b/], ['GTX', /\bgtx\s*\d{3,4}\b/],
      ['RX 5000', /\brx\s*5\d{3}\b/], ['RX 6000', /\brx\s*6\d{3}\b/],
      ['RX 7000', /\brx\s*7\d{3}\b/], ['RX 9000', /\brx\s*9\d{3}\b/],
    ]) if (pattern.test(words)) models.push(name);
    if (models.length === 1) return result(models[0], true);
    if (models.length > 1) return result('Bizonytalan');
    return /\b(?:quadro|firepro|tesla|radeon|geforce|arc|rx|r[579])\b/.test(words) ? result('Egyéb') : result('Bizonytalan');
  }
  return result('Bizonytalan');
}

function newDeviceCategory(group, suggestions) {
  const preferred = group === 'iphone' ? /handys|smartphones|mobile.*phones|cell.*phones/
    : group === 'gpu' ? /grafik.*karten|grafikkarten|graphics.*cards|video.*cards/
      : /spielkonsolen|videospielkonsolen|video.*consoles|game.*consoles/;
  const scored = suggestions.filter(entry => /^\d+$/.test(entry.id) && nonempty(entry.name))
    .filter(entry => !/zubehor|accessor|ersatz|parts|taschen|hullen|kuhler|controller|spiele$|games$/i.test(diagnosticTitleWords(entry.name)))
    .map((entry, index) => ({ ...entry, score: (preferred.test(diagnosticTitleWords(entry.name)) ? 100 : 0) - index }));
  return scored.sort((a, b) => b.score - a.score)[0] || null;
}

function newDeviceCoverage(jobs, relevantOnly = false) {
  const union = new Set(jobs.flatMap(job => [...job.items].filter(([, item]) =>
    !relevantOnly || item.classification.supported).map(([id]) => id)));
  const counts = new Map();
  for (const job of jobs) for (const id of job.items.keys()) if (union.has(id)) counts.set(id, (counts.get(id) || 0) + 1);
  return { union, rows: jobs.map(job => ({ query: job.query,
    covered: [...job.items.keys()].filter(id => union.has(id)).length,
    only: [...job.items.keys()].filter(id => counts.get(id) === 1).length })) };
}

function newDeviceRequest(job, token) {
  const params = { q: job.query, category_ids: job.category.id, limit: PAGE_SIZE, offset: job.pages * PAGE_SIZE,
    filter: 'conditionIds:{7000},deliveryCountry:HU,buyingOptions:{AUCTION|FIXED_PRICE},itemLocationCountry:' + job.country };
  return fetchOptions({ url: EBAY_ROOT + '/buy/browse/v1/item_summary/search?' + Object.entries(params)
    .map(([key, value]) => key + '=' + encodeURIComponent(value)).join('&'), method: 'get', headers: browseHeaders(token) });
}

function measureNewDeviceJobs(jobs, token, secrets, count, deadline) {
  const pending = jobs.slice();
  let used = 0;
  while (pending.length && Date.now() < deadline && used < 350) {
    const batch = pending.splice(0, Math.min(ebayFetchBatchSize(), 350 - used));
    try { count('browse', batch.length); }
    catch (error) {
      [...batch, ...pending.splice(0)].forEach(job => { job.error = error instanceof AppError ? error.message : 'Híváskerethiba.'; });
      break;
    }
    batch.forEach(job => { job.calls = (job.calls || 0) + 1; });
    used += batch.length;
    let responses;
    try { responses = UrlFetchApp.fetchAll(batch.map(job => newDeviceRequest(job, token))); }
    catch { batch.forEach(job => { job.error = 'Hálózati hiba vagy időtúllépés.'; }); continue; }
    for (const [index, job] of batch.entries()) {
      const response = responses[index];
      const data = response ? responseObject(response) : {};
      const status = response?.getResponseCode();
      const raw = data.itemSummaries === undefined ? [] : data.itemSummaries;
      const safe = Array.isArray(raw) ? [...secrets, ...raw.flatMap(item => sellerIdentities(item?.seller))] : secrets;
      if (data.warnings !== undefined) Logger.log(job.group + '/' + job.country + '/' + job.query +
        ' figyelmeztetés: ' + JSON.stringify(safeWarning(data.warnings, safe)));
      if (status === 429 && !job.retried) { job.retried = true; Utilities.sleep(1000); pending.push(job); continue; }
      if (status !== 200 || !Number.isSafeInteger(data.total) || data.total < 0 || !Array.isArray(raw)) {
        job.error = status !== 200 ? 'HTTP ' + (status || 'nincs válasz') : 'Hiányos eBay-válasz.';
        continue;
      }
      if (job.total === null) job.total = data.total;
      job.pages++;
      job.retried = false;
      for (const item of raw) {
        if (!record(item) || !nonempty(item.itemId)) continue;
        if (itemCountry(item) !== job.country || String(item.conditionId) !== '7000') { job.rejected++; continue; }
        const title = (redactContact(nonempty(item.title), safe) || '').replace(/\s+/g, ' ').trim();
        const [cost] = shipping(item);
        // Whitelist immediately: never retain a seller or a raw response.
        job.items.set(item.itemId, { title, country: job.country, known_shipping: cost !== null,
          classification: classifyNewDeviceTitle(job.group, title) });
      }
      if (data.total > job.pages * PAGE_SIZE) {
        if (raw.length && job.pages < PAGE_LIMIT) pending.push(job);
        else job.error = raw.length ? 'Ötoldalas mérési korlát.' : 'Hiányos lapozás.';
      }
    }
  }
  pending.forEach(job => { job.error = 'A diagnosztika idő- vagy híváskorlátja.'; });
}

function newDeviceShipping(items, token, secrets, count, deadline) {
  const eligible = [...items].filter(([, item]) => item.classification.supported);
  const unknown = eligible.filter(([, item]) => !item.known_shipping);
  // Round-robin over measured countries so a large DE result does not consume the whole sample.
  const byCountry = ['DE', 'FR', 'IT'].map(country => unknown.filter(([, item]) => item.country === country));
  const ordered = [];
  for (let index = 0; ordered.length < unknown.length; index++) {
    const next = byCountry.flatMap(items => items[index] ? [items[index]] : []);
    if (!next.length) break;
    ordered.push(...next);
  }
  const sample = (ordered.length ? ordered : unknown).slice(0, 10);
  const result = { supported: eligible.length, known: eligible.length - unknown.length,
    initial_unknown: unknown.length, sampled: 0, yes: 0, no: 0, unknown: 0, failed: 0 };
  for (let offset = 0; offset < sample.length && Date.now() < deadline; offset += ebayFetchBatchSize()) {
    const batch = sample.slice(offset, offset + ebayFetchBatchSize());
    count('get_item', batch.length);
    result.sampled += batch.length;
    let responses;
    try { responses = UrlFetchApp.fetchAll(batch.map(([id]) => fetchOptions({
      url: EBAY_ROOT + '/buy/browse/v1/item/' + encodeURIComponent(id), method: 'get', headers: browseHeaders(token),
    }))); } catch { result.unknown += batch.length; result.failed += batch.length; continue; }
    for (const [index, [id]] of batch.entries()) {
      const response = responses[index];
      const data = response ? responseObject(response) : {};
      if (data.warnings !== undefined) Logger.log('getItem figyelmeztetés: ' +
        JSON.stringify(safeWarning(data.warnings, [...secrets, ...sellerIdentities(data.seller)])));
      if (response?.getResponseCode() !== 200 || data.itemId !== id) { result.unknown++; result.failed++; continue; }
      result[shipsToHungary(data.shipToLocations)]++;
    }
  }
  return result;
}

function reportNewDeviceGroup(group, jobs, shippingResult, calls) {
  const config = NEW_DEVICE_DIAGNOSTIC[group];
  const union = new Map(jobs.flatMap(job => [...job.items]));
  const examples = [];
  for (const country of ['DE', 'FR', 'IT']) {
    const scoped = jobs.filter(job => job.country === country);
    const coverage = newDeviceCoverage(scoped);
    scoped.forEach((job, index) => Logger.log(group + '/' + country + ' | ' + job.query +
      ' | total=' + (job.total ?? 'Nem ismert') + ' | lefedettség=' + coverage.rows[index].covered + '/' + coverage.union.size +
      ' | csak ennél=' + coverage.rows[index].only + ' | oldalak=' + job.pages + ' | eltérő hely/állapot=' + job.rejected +
      (job.error ? ' | RÉSZLEGES: ' + job.error : '')));
  }
  const categories = new Map(NEW_DEVICE_CATEGORIES[group].map(category => [category, []]));
  for (const item of union.values()) {
    const key = item.classification.category;
    if (!categories.has(key)) categories.set(key, []);
    categories.get(key).push(item);
  }
  Logger.log(config.name + ' címbesorolás (' + union.size + ' egyedi):');
  for (const [category, items] of categories) {
    Logger.log('  ' + category + ': ' + items.length);
    for (const item of items.slice(0, 8)) {
      Logger.log('    [' + item.country + '] ' + item.title);
      examples.push({ device_group: group, country: item.country, title: item.title, diagnostic: item.classification });
    }
  }
  if (group === 'iphone') {
    const locked = [...union.values()].filter(item => item.classification.lock_mentioned);
    Logger.log('iCloud-/aktiválási zárat említ: ' + locked.length + '. Ez említés, nem igazolt zár vagy zármentesség.');
    locked.slice(0, 5).forEach(item => {
      Logger.log('  ' + item.title);
      if (!examples.some(row => row.title === item.title)) examples.push({ device_group: group,
        country: item.country, title: item.title, diagnostic: item.classification });
    });
    for (const generation of [15, 16, 17]) Logger.log('iPhone ' + generation + ': ' +
      [...union.values()].filter(item => new RegExp('^iPhone ' + generation + '\\b').test(item.classification.model)).length);
  }
  // Merge each keyword across all three countries before finding the smallest full cover.
  const merged = config.queries.map(query => {
    const same = jobs.filter(job => job.query === query);
    return { query, pages: same.reduce((sum, job) => sum + job.pages, 0), items: new Map(same.flatMap(job => [...job.items])) };
  });
  const target = new Set([...union].filter(([, item]) => item.classification.supported).map(([id]) => id));
  const best = bestControllerKeywords(merged, target);
  const relevant = ['DE', 'FR', 'IT'].map(country => country + ':' +
    [...union.values()].filter(item => item.country === country && item.classification.supported).length).join(', ');
  Logger.log(config.name + ' szállítás: felismert támogatott=' + shippingResult.supported + ', eleve ismert HU-díj=' + shippingResult.known +
    ', ismeretlen díjú=' + shippingResult.initial_unknown + ', getItem-minta=' + shippingResult.sampled +
    ', HU igen/nem/nem eldönthető=' + shippingResult.yes + '/' + shippingResult.no + '/' + shippingResult.unknown +
    ', sikertelen=' + shippingResult.failed);
  if (shippingResult.sampled < Math.min(10, shippingResult.initial_unknown)) {
    Logger.log(config.name + ': időkorlát miatt a szállítási minta hiányos.');
  }
  const partial = jobs.some(job => job.error);
  const selected = jobs[0]?.category;
  const estimate = best.keywords.length * 27;
  const ratio = shippingResult.sampled ? shippingResult.yes + '/' + shippingResult.sampled + ' (getItem-minta)' : 'nincs getItem-minta';
  const row = [config.name, selected ? selected.id + ' ' + selected.name : 'nincs kategória',
    best.keywords.join('; ') || 'nincs megalapozott javaslat', relevant, ratio,
    best.keywords.length ? estimate + ' első oldal; lapozással kb. ' + Math.ceil(best.pages / 3 * 27) +
      '; hideg cache getItem kb. ' + Math.min(100, shippingResult.initial_unknown * 9) + ' (a jelenlegi közös 100-as korláttal)' : 'nem becsülhető', calls];
  Logger.log('Javaslat ' + config.name + ': ' + best.keywords.join('; ') + ' | releváns lefedettség=' + best.count + '/' + target.size +
    ' | országonként ' + best.keywords.length + ' első oldal' + (partial ? ' | RÉSZLEGES, csak a lekért mintára érvényes.' : ' | DE/FR/IT mintára érvényes.'));
  return { row: row.join(' | ') + (partial ? ' | RÉSZLEGES' : ''), examples };
}

function diagnoseNewDeviceGroups() {
  const calls = { oauth: 0, taxonomy: 0, browse: 0, get_item: 0 };
  const count = (kind, amount) => { dailyCounter(kind === 'get_item' ? 'browse' : kind, amount); calls[kind] += amount; };
  const examples = [];
  const summary = ['Csoport | Kategória | Javasolt q | Releváns országonként | HU-arány | 27 ország hívásbecslés | Mért keresés+getItem'];
  const deadline = Date.now() + 270000;
  try {
    const token = applicationToken(ebayCredentials(), count);
    const secrets = [...notificationSecrets(PropertiesService.getScriptProperties()), token];
    const taxonomyGet = path => {
      count('taxonomy', 1);
      const response = fetchEbay(EBAY_ROOT + '/commerce/taxonomy/v1/' + path, { method: 'get', headers: browseHeaders(token) });
      const data = responseObject(response);
      if (data.warnings !== undefined) Logger.log('Taxonomy: ' + JSON.stringify(safeWarning(data.warnings, secrets)));
      if (response.getResponseCode() !== 200) throw new AppError('diagnostic_taxonomy', 'Taxonomy HTTP ' + response.getResponseCode());
      return data;
    };
    const tree = taxonomyGet('get_default_category_tree_id?marketplace_id=EBAY_DE').categoryTreeId;
    if (!/^\d+$/.test(String(tree))) throw new AppError('diagnostic_taxonomy', 'Hiányzik az EBAY_DE kategóriafa.');
    const categories = new Map();
    for (const [group, config] of Object.entries(NEW_DEVICE_DIAGNOSTIC)) {
      try {
        const data = taxonomyGet('category_tree/' + tree + '/get_category_suggestions?q=' + encodeURIComponent(config.taxonomy));
        const list = (Array.isArray(data.categorySuggestions) ? data.categorySuggestions : []).map(entry => ({
          id: String(entry?.category?.categoryId || ''), name: redactContact(nonempty(entry?.category?.categoryName), secrets),
        })).filter(entry => /^\d+$/.test(entry.id) && entry.name);
        Logger.log(config.name + ' kategóriajavaslatok: ' + list.map(entry => entry.id + ' – ' + entry.name).join('; '));
        const best = newDeviceCategory(group, list);
        Logger.log(config.name + ' kiválasztott kategória: ' + (best ? best.id + ' – ' + best.name : 'Nincs megfelelő javaslat, a csoport kimarad.'));
        if (best) categories.set(group, best);
      } catch (error) { Logger.log(config.name + ': ' + (error instanceof AppError ? error.message : 'Taxonomy-hiba.')); }
    }
    const jobs = [...categories].flatMap(([group, category]) => ['DE', 'FR', 'IT'].flatMap(country =>
      NEW_DEVICE_DIAGNOSTIC[group].queries.map(query => ({ group, category, country, query, pages: 0,
        total: null, items: new Map(), rejected: 0 }))));
    measureNewDeviceJobs(jobs, token, secrets, count, deadline - 45000);
    for (const [group] of Object.entries(NEW_DEVICE_DIAGNOSTIC)) {
      const scoped = jobs.filter(job => job.group === group);
      if (!scoped.length) { summary.push(NEW_DEVICE_DIAGNOSTIC[group].name + ' | KIMARADT: nincs kategória.'); continue; }
      const union = new Map(scoped.flatMap(job => [...job.items]));
      const before = calls.get_item;
      const shippingResult = newDeviceShipping(union, token, secrets, count, deadline);
      const used = scoped.reduce((sum, job) => sum + (job.calls || 0), 0) + calls.get_item - before;
      const report = reportNewDeviceGroup(group, scoped, shippingResult, used);
      summary.push(report.row);
      examples.push(...report.examples);
    }
  } catch (error) { Logger.log(error instanceof AppError ? error.message : 'Az új eszközcsoportok mérése megszakadt.'); }
  finally {
    Logger.log('Csoport | Kategória | Javasolt lekérdezések | Releváns országonként | HU-arány | 27 ország becsült hívásai | Felhasznált Browse+getItem');
    Logger.log(summary.join('\n'));
    Logger.log('A HU-arány célzott, legfeljebb 10 elemű ismeretlendíj-minta, nem a teljes kínálat aránya. A hívásbecslés 3 ország egyszerű 9-szeres kivetítése, nem garancia; nem tartalmaz OAuth-ot és Taxonomyt. A getItem 100-as korlátja jelenleg keresésenként közös.');
    Logger.log('eBay API-hívások: ' + Object.values(calls).reduce((sum, value) => sum + value, 0) +
      ' (OAuth: ' + calls.oauth + ', Taxonomy: ' + calls.taxonomy + ', Browse keresés: ' + calls.browse + ', getItem: ' + calls.get_item + ').');
    const date = Utilities.formatDate(new Date(), 'Europe/Budapest', 'yyyy-MM-dd');
    Logger.log('Fixture-fájlnév: apps_script/test/fixtures/new_device_titles_live_' + date + '.json');
    // A single JSON line, containing only redacted titles and diagnostic classifications.
    const fixture = { date, diagnostic_only: true, examples };
    Logger.log(JSON.stringify(fixture));
    // The editor can truncate long log entries. Bounded chunks preserve every example.
    if (JSON.stringify(fixture).length > 6500) {
      let chunk = [];
      let part = 1;
      for (const example of examples) {
        if (JSON.stringify([...chunk, example]).length > 6000) {
          Logger.log('FIXTURE_PART_' + part++ + ': ' + JSON.stringify(chunk));
          chunk = [];
        }
        chunk.push(example);
      }
      if (chunk.length) Logger.log('FIXTURE_PART_' + part + ': ' + JSON.stringify(chunk));
    }
  }
}
