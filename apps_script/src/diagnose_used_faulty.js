const USED_FAULT_WORDS = {
  DE: ['defekt', 'kaputt', 'bastler'], AT: ['defekt', 'kaputt', 'bastler'],
  FR: ['hs', 'panne', 'pour pièces'], BE: ['hs', 'panne', 'pour pièces'],
  IT: ['guasto', 'difettoso', 'non funzionante'], ES: ['averiado', 'para piezas'],
  NL: ['defect', 'kapot'], PL: ['uszkodzony'],
};
const USED_FAULT_MODELS = {
  consoles: ['ps5', 'xbox series'], controllers: ['ps5 controller', 'xbox controller'],
};
const USED_CONDITION_IDS = ['2000', '2010', '2020', '2030', '2500', '2750', '3000', '4000', '5000', '6000'];

function diagnosticTitleWords(value) {
  return value.toLowerCase().normalize('NFD').replace(/\p{M}/gu, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/\bh s\b/g, 'hs').trim();
}

function isDiagnosticFaultTitle(title, keywords) {
  const words = diagnosticTitleWords(title);
  const denial = /\b(?:nicht defekt|kein(?:e[rmns]?)? defekt[e]?|ohne defekt[e]?|defektfrei|funktioniert einwandfrei|voll funktionsfahig|einwandfrei funktionsfahig|sans panne|pas (?:du tout )?hs|non hs|pas en panne|non guasto|non difettoso|funziona perfettamente|no averiado|sin averias?|geen defect|niet kapot|werkt perfect|nieuszkodzony|nie uszkodzony)\b/;
  if (denial.test(words)) return false;
  return keywords.some(keyword => {
    const word = diagnosticTitleWords(keyword);
    const suffix = ['defekt', 'guasto', 'difettoso', 'averiado', 'uszkodzony'].includes(word) ? '[a-z]*' : '';
    return new RegExp('(?:^| )' + word + suffix + '(?: |$)').test(words);
  });
}

function diagnosticUsedPolicies(token, secrets, count) {
  const filter = 'categoryIds:{' + Object.values(DEVICE_GROUPS).map(group => group.category).join('|') + '}';
  count('metadata', 1);
  const response = fetchEbay(EBAY_ROOT + '/sell/metadata/v1/marketplace/EBAY_DE/get_item_condition_policies?filter=' +
    encodeURIComponent(filter), { method: 'get', headers: browseHeaders(token) });
  const payload = responseObject(response);
  if (payload.warnings !== undefined) Logger.log('Metadata: ' + JSON.stringify(safeWarning(payload.warnings, secrets)));
  if (response.getResponseCode() !== 200 || !Array.isArray(payload.itemConditionPolicies)) {
    throw new AppError('used_condition_policy', 'Az állapotlista nem ellenőrizhető (Metadata HTTP ' +
      response.getResponseCode() + ').');
  }
  const result = new Map();
  for (const [group, config] of Object.entries(DEVICE_GROUPS)) {
    const policy = payload.itemConditionPolicies.find(entry => String(entry.categoryId) === config.category);
    const conditions = Array.isArray(policy?.itemConditions) ? policy.itemConditions.filter(condition =>
      USED_CONDITION_IDS.includes(String(condition.conditionId))) : [];
    if (!conditions.length) {
      Logger.log(group + ' (' + config.category + '): nincs visszaigazolt használt állapot.');
      continue;
    }
    const ids = [...new Set(conditions.map(condition => String(condition.conditionId)))];
    result.set(group, ids);
    Logger.log(group + ' (' + config.category + '), használt állapotok: ' + conditions.map(condition =>
      condition.conditionId + ' ' + (redactContact(condition.conditionDescription, secrets) || '')).join('; '));
  }
  Logger.log('Az application tokennel nem látható felújított állapotok kimaradnak a mérésből.');
  return result;
}

function usedDiagnosticRequest(job, token) {
  const filter = 'conditionIds:{' + job.conditions.join('|') + '},deliveryCountry:HU,itemLocationCountry:' +
    job.country + ',buyingOptions:{AUCTION|FIXED_PRICE}';
  const params = { q: job.query, category_ids: DEVICE_GROUPS[job.group].category, limit: PAGE_SIZE,
    offset: job.pages * PAGE_SIZE, filter };
  const query = Object.entries(params).map(([key, value]) => key + '=' + encodeURIComponent(value)).join('&');
  return fetchOptions({ url: EBAY_ROOT + '/buy/browse/v1/item_summary/search?' + query,
    method: 'get', headers: browseHeaders(token) });
}

function measureUsedDiagnostic(jobs, token, secrets, count, deadline) {
  let pending = jobs.slice();
  const size = ebayFetchBatchSize();
  while (pending.length && Date.now() < deadline) {
    const batch = pending.splice(0, size);
    try {
      count('browse', batch.length);
    } catch (error) {
      if (!(error instanceof AppError)) throw error;
      [...batch, ...pending].forEach(job => { job.error = error.message; });
      return;
    }
    let responses;
    try {
      responses = UrlFetchApp.fetchAll(batch.map(job => usedDiagnosticRequest(job, token)));
    } catch {
      batch.forEach(job => { job.error = 'Hálózati hiba'; });
      continue;
    }
    for (const [index, job] of batch.entries()) {
      const response = responses[index];
      const status = response?.getResponseCode();
      const data = response ? responseObject(response) : {};
      const raw = data.itemSummaries === undefined ? [] : data.itemSummaries;
      const safe = Array.isArray(raw) ? [...secrets, ...raw.flatMap(item => sellerIdentities(item?.seller))] : secrets;
      if (data.warnings !== undefined) {
        Logger.log(job.country + '/' + job.group + ' / ' + job.query + ': ' + JSON.stringify(safeWarning(data.warnings, safe)));
      }
      if (status === 429 && !job.retried) {
        job.retried = true;
        Utilities.sleep(1000);
        pending.push(job);
        continue;
      }
      if (status !== 200 || !Number.isSafeInteger(data.total) || data.total < 0 || !Array.isArray(raw)) {
        job.error = status !== 200 ? 'HTTP ' + (status || 'nincs válasz') : 'Érvénytelen eBay-válasz';
        continue;
      }
      if (job.total === null) job.total = data.total;
      job.pages++;
      job.retried = false;
      for (const item of raw) {
        if (itemCountry(item || {}) !== job.country || !job.conditions.includes(String(item.conditionId)) ||
            !nonempty(item.itemId)) continue;
        job.items.set(item.itemId, (redactContact(nonempty(item.title), safe) || '').replace(/\s+/g, ' ').trim());
      }
      if (data.total > job.pages * PAGE_SIZE) {
        if (raw.length && job.pages < PAGE_LIMIT) pending.push(job);
        else job.error = raw.length ? 'Ötoldalas korlát' : 'Hiányos lapozás';
      }
    }
  }
  pending.forEach(job => { job.error = 'Időkorlát'; });
}

function reportUsedDiagnostic(jobs) {
  const summary = ['Ország | Csoport | 7000-es egyedi | Új egyedi | Cím szerint hibás | Javasolt lekérdezések | Hívás (első oldalak / mért oldalak)'];
  const scopes = new Set(jobs.map(job => job.country + '/' + job.group));
  for (const scope of scopes) {
    const [country, group] = scope.split('/');
    const scoped = jobs.filter(job => job.country === country && job.group === group);
    const baseline = scoped.filter(job => !job.keyword);
    const known = new Set(baseline.flatMap(job => [...job.items.keys()]));
    const complete = baseline.every(job => !job.error) && scoped.every(job => !job.error);
    const extras = new Set();
    const faults = new Set();
    const recommendations = [];
    for (const job of scoped) {
      const added = job.keyword ? [...job.items].filter(([id]) => !known.has(id)) : [];
      const faulty = new Map(added.filter(([, title]) => isDiagnosticFaultTitle(title, USED_FAULT_WORDS[country])));
      added.forEach(([id]) => extras.add(id));
      faulty.forEach((_, id) => faults.add(id));
      if (job.keyword) recommendations.push({ query: job.query, items: faulty, pages: job.pages });
      Logger.log(scope + ' | ' + (job.keyword ? 'használt' : '7000') + ' | ' + job.query + ' | total=' +
        (job.total ?? '—') + ' | ellenőrzött hely és állapot=' + job.items.size +
        (job.keyword ? ' | új=' + added.length + ' | cím szerint hibás=' + faulty.size : '') +
        (job.error ? ' | részleges: ' + job.error : ''));
      const classify = group === 'controllers' ? classifyController : classifyItem;
      added.slice(0, 10).forEach(([id, title]) => {
        const classification = classify(title);
        Logger.log('  ' + (title || '(cím nélkül)') + ' → ' + classification.item_type +
          ' / ' + classification.console_model + (faulty.has(id) ? ' | cím szerint hibás' : ''));
      });
    }
    const best = bestControllerKeywords(recommendations, faults);
    const measuredBaseline = baseline.reduce((sum, job) => sum + job.pages, 0);
    summary.push([country, group, known.size, extras.size, faults.size, best.keywords.join(', ') || '—',
      best.keywords.length + ' / ' + best.pages + ' (+ meglévő ' + baseline.length + ' / ' + measuredBaseline + ')',
      ...(complete ? [] : ['részleges minta'])].join(' | '));
  }
  Logger.log(summary.join('\n'));
}

function diagnoseUsedFaulty() {
  const calls = { oauth: 0, metadata: 0, browse: 0 };
  const count = (kind, amount) => {
    dailyCounter(kind, amount);
    calls[kind] += amount;
  };
  try {
    const token = applicationToken(ebayCredentials(), count);
    const secrets = [...notificationSecrets(PropertiesService.getScriptProperties()), token];
    const policies = diagnosticUsedPolicies(token, secrets, count);
    const jobs = [];
    for (const country of ['DE', 'FR', 'IT', 'NL']) {
      for (const [group, conditions] of policies) {
        for (const query of DEVICE_GROUPS[group].queries) jobs.push({ country, group, query, conditions: ['7000'] });
        for (const model of USED_FAULT_MODELS[group]) {
          for (const keyword of USED_FAULT_WORDS[country]) jobs.push({ country, group,
            query: model + ' ' + keyword, keyword, conditions });
        }
      }
    }
    const states = jobs.map(job => ({ ...job, pages: 0, total: null, items: new Map() }));
    measureUsedDiagnostic(states, token, secrets, count, Date.now() + 250000);
    reportUsedDiagnostic(states);
  } catch (error) {
    Logger.log(error instanceof AppError ? error.message : 'A használt hibás tételek mérése megszakadt.');
  } finally {
    Logger.log('eBay API-hívások: ' + (calls.oauth + calls.metadata + calls.browse) + ' (OAuth: ' + calls.oauth +
      ', Metadata: ' + calls.metadata + ', Browse: ' + calls.browse + ').');
  }
}
