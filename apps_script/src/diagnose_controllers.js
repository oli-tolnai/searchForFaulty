const CONTROLLER_KEYWORDS = [
  'dualsense', 'ps5 controller', 'dualsense edge',
  'xbox series controller', 'xbox wireless controller', 'xbox elite controller',
];
const CONTROLLER_GROUPS = [
  'DualSense', 'DualSense Edge', 'Xbox Series kontroller', 'Xbox Elite Series 2',
  'Régi generáció', 'Nem kontroller', 'Csomag', 'Bizonytalan',
];

function classifyControllerTitle(title, includeBundles = true) {
  const text = title.toLowerCase().replace(/[‐‑–—]/g, '-')
    .replace(/\b(\d+)[x×](?=dualsense|controller|xbox|ps5)/g, '$1x ');
  const controller = /\b(?:dualsense|dual\s*shock|controller|kontroller|gamepad|manette|game\s*pad)\b/;
  const accessory = /\b(?:ladestation|ladegerät|ladekabel|charging (?:dock|station)|charger|dock|schutzhülle|tasche|case|cover|akku|battery|gehäuse|shell|ersatzteile?|spare parts?|thumb\s*sticks?|sticks? modules?|stickmodul|hall effect sensors?|paddles?|platine|mainboard|motherboard|trigger (?:spring|assembly)|usb(?:-c)? (?:port|buchse)|replacement buttons?)\b/;
  const accessoryOnly = /\b(?:only|nur|allein|solamente)\s+(?:der |die |das |the )?(?:ladestation|ladegerät|gehäuse|shell|akku|battery|case|cover|stickmodul|platine|paddles?)\b|\b(?:ohne|without|sans)\s+(?:den |the |a )?(?:controller|kontroller|gamepad|manette)\b/;
  const bundledAccessory = /\b(?:with|mit|inkl\.?|including|plus|avec)\s+(?:original[emrs]?\s+)?(?:ladestation|ladegerät|ladekabel|charging (?:dock|station)|charger|dock|schutzhülle|tasche|case|cover|akku|battery|gehäuse|shell|stickmodul|paddles?)\b/;
  const modelCode = /\b(?:cfi[\s-]*zc(?:t|p)1[a-z]?|(?:model(?:l)?\s*[:#]?\s*)?(?:1914|1797|1708|1697|1537))\b/;
  if (accessoryOnly.test(text) ||
      (accessory.test(text) && !/\b(?:für|for|pour)\s+(?:ersatzteile|spare parts|parts)\b/.test(text) &&
        !((controller.test(text) || modelCode.test(text)) && bundledAccessory.test(text))) ||
      (!controller.test(text) && !modelCode.test(text) && /\b(?:spielkonsole|konsole|console)\b/.test(text))) {
    return 'Nem kontroller';
  }
  const families = [
    /\bcfi[\s-]*zct1[a-z]?\b/,
    /\bcfi[\s-]*zcp1[a-z]?\b/,
    /\b1914\b/,
    /\b1797\b/,
    /\b(?:1708|1697|1537)\b/,
  ];
  const explicit = families.flatMap((pattern, index) => pattern.test(text) ? [index] : []);
  const edge = /\bdualsense\s+edge\b/.test(text);
  const elite = /\belite(?:\s+(?:wireless|controller|series|serie|v|modell?))*[\s-]*(?:2|ii)\b/.test(text);
  const old = /\b(?:ps\s*4|playstation\s*4|dual\s*shock\s*4|xbox\s*(?:one|360))\b/.test(text);
  const possible = [
    !edge && /\bdualsense\b|\b(?:ps\s*5|playstation\s*5)\s+(?:wireless\s+)?(?:controller|kontroller|manette)\b/.test(text),
    edge,
    !elite && /\bxbox\b/.test(text) && /\bseries\b/.test(text) && controller.test(text),
    elite,
    old,
  ].flatMap((matches, index) => matches ? [index] : []);
  const selected = explicit.length ? explicit : possible;
  const quantities = text.replace(/\b(?:dual\s*shock\s*4|series\s*2|xbox\s*360|playstation\s*[45])\b/g, ' ');
  if (includeBundles && (controller.test(text) || selected.some(index => index < 4)) &&
      /\b(?:lot|posten|konvolut|bundle of|mehrere|multiple|2er|3er|pack of)\b|\b(?:[2-9]|[1-9]\d+)\s*(?:[x×](?![a-z0-9])|stück\b|pcs\b|controller\b|kontroller\b)/.test(quantities)) {
    return 'Csomag';
  }
  return selected.length === 1 ? CONTROLLER_GROUPS[selected[0]] : 'Bizonytalan';
}

function controllerCategory(suggestions) {
  const candidates = new Map();
  for (const categories of suggestions) {
    categories.forEach(({ id, name }, index) => {
      if (!/controller|gamepads?|joysticks?|manettes?|kontroller/i.test(name) ||
          /ersatz|parts?|teile|schutzhüll|zubehör|accessor|case|cables?|kabel/i.test(name)) return;
      const score = candidates.get(id) || { id, name, hits: 0, rank: 0 };
      score.hits++;
      score.rank += index;
      candidates.set(id, score);
    });
  }
  return [...candidates.values()].sort((a, b) => b.hits - a.hits || a.rank - b.rank || a.id.localeCompare(b.id))[0];
}

function controllerBrowseRequest(job, token) {
  const params = {
    q: job.query, limit: PAGE_SIZE, offset: job.pages * PAGE_SIZE,
    filter: 'conditionIds:{7000},deliveryCountry:HU,itemLocationCountry:DE,buyingOptions:{AUCTION|FIXED_PRICE}',
  };
  if (job.category) params.category_ids = job.category;
  const query = Object.entries(params).map(([key, val]) => key + '=' + encodeURIComponent(val)).join('&');
  return fetchOptions({ url: EBAY_ROOT + '/buy/browse/v1/item_summary/search?' + query,
    method: 'get', headers: browseHeaders(token) });
}

function measureControllerQueries(specs, token, secrets, count) {
  const jobs = specs.map(spec => ({ ...spec, pages: 0, total: null, extra: 0, items: new Map(), error: null }));
  const label = job => '"' + job.query + '"' + (job.category ? '' : ' kategória nélkül');
  let pending = jobs.slice();
  const size = ebayFetchBatchSize();
  while (pending.length) {
    const next = [];
    for (let start = 0; start < pending.length; start += size) {
      const batch = pending.slice(start, start + size);
      count('browse', batch.length);
      let responses;
      try {
        responses = UrlFetchApp.fetchAll(batch.map(job => controllerBrowseRequest(job, token)));
      } catch {
        batch.forEach(job => { job.error = 'Hálózati hiba a keresési kötegben.'; });
        continue;
      }
      batch.forEach((job, index) => {
        const response = responses[index];
        const status = response.getResponseCode();
        const data = responseObject(response);
        const items = data.itemSummaries === undefined ? [] : data.itemSummaries;
        const safe = Array.isArray(items) ? [...secrets, ...items.flatMap(item => sellerIdentities(item?.seller))] : secrets;
        if (data.warnings !== undefined) Logger.log(label(job) + ' figyelmeztetései: ' + JSON.stringify(safeWarning(data.warnings, safe)));
        if (status !== 200 || !Number.isSafeInteger(data.total) || data.total < 0 || !Array.isArray(items)) {
          job.error = status !== 200 ? 'HTTP ' + status : 'Hiányos eBay-válasz.';
          return;
        }
        if (job.total === null) job.total = data.total;
        job.pages++;
        for (const item of items) {
          if (item?.itemLocation?.country !== 'DE') {
            job.extra++;
            continue;
          }
          if (!nonempty(item.itemId) || job.items.has(item.itemId)) continue;
          const title = typeof item.title === 'string' ? redactContact(item.title, safe) : '';
          job.items.set(item.itemId, title.replace(/\s+/g, ' ').trim());
        }
        if (data.total > job.pages * PAGE_SIZE) {
          if (items.length && job.pages < PAGE_LIMIT) next.push(job);
          else job.error = items.length ? 'Elérte az ötoldalas mérési korlátot.' : 'Hiányos lapozás.';
        }
      });
    }
    pending = next;
  }
  for (const job of jobs) if (job.error) Logger.log(label(job) + ': ' + job.error);
  return jobs;
}

function bestControllerKeywords(jobs, target) {
  let best = { keywords: [], count: 0, pages: 0 };
  if (!target.size) return best;
  for (let mask = 1; mask < 1 << jobs.length; mask++) {
    const used = jobs.filter((job, index) => mask & (1 << index));
    const covered = new Set(used.flatMap(job => [...job.items.keys()].filter(id => target.has(id))));
    const pages = used.reduce((sum, job) => sum + job.pages, 0);
    if (covered.size > best.count || (covered.size === best.count &&
        (used.length < best.keywords.length || (used.length === best.keywords.length && pages < best.pages)))) {
      best = { keywords: used.map(job => job.query), count: covered.size, pages };
    }
  }
  return best;
}

function diagnoseControllers() {
  const calls = { oauth: 0, taxonomy: 0, browse: 0 };
  const count = (kind, amount) => {
    dailyCounter(kind, amount);
    calls[kind] += amount;
  };
  try {
    const credentials = ebayCredentials();
    const token = applicationToken(credentials, count);
    const secrets = [...notificationSecrets(PropertiesService.getScriptProperties()), token];
    const taxonomy = '/commerce/taxonomy/v1/';
    const taxonomyGet = path => {
      count('taxonomy', 1);
      const response = fetchEbay(EBAY_ROOT + taxonomy + path, { method: 'get', headers: browseHeaders(token) });
      const data = responseObject(response);
      if (data.warnings !== undefined) Logger.log('Taxonomy-figyelmeztetés: ' + JSON.stringify(safeWarning(data.warnings, secrets)));
      if (response.getResponseCode() !== 200) {
        throw new AppError('controller_taxonomy', 'A Taxonomy-hívás sikertelen (HTTP ' + response.getResponseCode() + ').');
      }
      return data;
    };
    let tree;
    try {
      tree = taxonomyGet('get_default_category_tree_id?marketplace_id=EBAY_DE').categoryTreeId;
    } catch (error) {
      if (!(error instanceof AppError)) throw error;
      Logger.log(error.message);
    }
    const validTree = typeof tree === 'string' && /^\d+$/.test(tree);
    Logger.log('EBAY_DE alapértelmezett kategóriafa: ' + (validTree ? tree : 'nem áll rendelkezésre'));
    const suggestions = !validTree ? [] : ['DualSense controller', 'Xbox wireless controller'].map(query => {
      let data;
      try {
        data = taxonomyGet('category_tree/' + tree + '/get_category_suggestions?q=' + encodeURIComponent(query));
      } catch (error) {
        if (!(error instanceof AppError)) throw error;
        Logger.log('Kategóriajavaslatok (' + query + '): ' + error.message);
        return [];
      }
      const categories = new Map();
      for (const entry of Array.isArray(data.categorySuggestions) ? data.categorySuggestions : []) {
        const id = entry?.category?.categoryId;
        const name = entry?.category?.categoryName;
        if (typeof id === 'string' && /^\d+$/.test(id) && nonempty(name)) {
          categories.set(id, redactContact(name, secrets));
        }
      }
      const list = [...categories].map(([id, name]) => ({ id, name }));
      Logger.log('Kategóriajavaslatok (' + query + '): ' + (list.map(row => row.id + ' – ' + row.name).join('; ') || 'nincs'));
      return list;
    });
    const category = controllerCategory(suggestions);
    if (!category) Logger.log('Nem sikerült kontroller-kategóriát azonosítani. A kategória nélküli keresések következnek.');
    else Logger.log('Kiválasztott kategória: ' + category.id + ' – ' + category.name);
    const specs = category ? CONTROLLER_KEYWORDS.map(query => ({ query, category: category.id })) : [];
    specs.push(...['dualsense', 'xbox series controller'].map(query => ({ query, category: null })));
    const jobs = measureControllerQueries(specs, token, secrets, count);
    reportControllerMeasurement(jobs);
  } catch (error) {
    Logger.log(error instanceof AppError ? error.message : 'A kontrollermérés váratlan hiba miatt megszakadt.');
  } finally {
    Logger.log('eBay API-hívások: ' + (calls.oauth + calls.taxonomy + calls.browse) +
      ' (OAuth: ' + calls.oauth + ', Taxonomy: ' + calls.taxonomy + ', Browse: ' + calls.browse + ').');
  }
}

function reportControllerMeasurement(jobs) {
  const categorized = jobs.filter(job => job.category);
  const union = new Map(categorized.flatMap(job => [...job.items]));
  const counts = new Map();
  for (const job of categorized) {
    for (const id of job.items.keys()) counts.set(id, (counts.get(id) || 0) + 1);
  }
  for (const job of categorized) {
    const unique = [...job.items.keys()].filter(id => counts.get(id) === 1).length;
    Logger.log('"' + job.query + '": total=' + (job.total ?? 'nem ismert') + ', lefedettség=' +
      job.items.size + '/' + union.size + ', csak ennél=' + unique + ', oldalak=' + job.pages +
      ', eltérő/ismeretlen hely=' + job.extra + (job.error ? ' (részleges)' : ''));
  }
  for (const job of jobs.filter(job => !job.category)) {
    const same = categorized.find(other => other.query === job.query);
    const extras = same?.total != null ? [...job.items].filter(([id]) => !same.items.has(id)) : null;
    const outsideUnion = extras?.filter(([id]) => !union.has(id));
    Logger.log('"' + job.query + '" kategória nélkül: total=' + (job.total ?? 'nem ismert') +
      ', német találat=' + job.items.size + ', eltérő/ismeretlen hely=' + job.extra +
      (extras ? '; kategóriával, azonos kulcsszónál hiányzik: ' + extras.length +
        '; a teljes kategóriás mintából hiányzik: ' + outsideUnion.length : '; összehasonlítás nem érhető el') +
      (job.error || categorized.some(other => other.error) ? ' (részleges)' : ''));
    if (extras) [...outsideUnion, ...extras.filter(([id]) => union.has(id))].slice(0, 10).forEach(([, title]) =>
      Logger.log('  ' + (title || '(a cím hiányzik)')));
  }
  const sample = categorized.length ? union : new Map(jobs.flatMap(job => [...job.items]));
  const groups = new Map(CONTROLLER_GROUPS.map(group => [group, []]));
  const supported = new Set();
  for (const [id, title] of sample) {
    const group = classifyControllerTitle(title);
    groups.get(group).push(title);
    const model = group === 'Csomag' ? classifyControllerTitle(title, false) : group;
    if (CONTROLLER_GROUPS.slice(0, 4).includes(model)) supported.add(id);
  }
  Logger.log('Címbesorolás: ' + sample.size + ' egyedi tétel' + (categorized.length ? ' a kategóriás mintában.' : ' a kategória nélküli mintában.'));
  for (const [group, titles] of groups) {
    Logger.log(group + ': ' + titles.length);
    titles.slice(0, 8).forEach(title => Logger.log('  ' + (title || '(a cím hiányzik)')));
  }
  if (!categorized.length || categorized.some(job => job.total === null) || !union.size) {
    Logger.log('A kategóriás minta hiányos vagy üres, ezért egyelőre nincs kulcsszójavaslat.');
    return;
  }
  for (const [label, target] of [['teljes kategóriás minta', new Set(union.keys())], ['felismert támogatott modellek, csomagokkal', supported]]) {
    const best = bestControllerKeywords(categorized, target);
    if (!best.keywords.length) continue;
    Logger.log('Javaslat (' + label + (categorized.some(job => job.error) ? ', részleges mérés' : '') +
      '): ' + best.keywords.join(', ') + ' – ' + best.count + '/' + target.size +
      ' tétel; országonként ' + best.keywords.length + ' első oldalas hívás, DE-ben lapozással ' + best.pages + '.');
  }
}
