const PAGE_SIZE = 200;
const PAGE_LIMIT = 5;
const RUN_LIMIT = 59;
const SEARCH_TIME_LIMIT_MS = 300000;
const BUDGET_MESSAGE = 'A keresés elérte a futásonkénti híváskeretet.';
const ITEM_TYPES = [
  'console', 'console_bundle', 'mainboard', 'not_console', 'unsupported_model', 'needs_review',
];

function makeSearchRequest(job, token) {
  const params = {
    q: job.state.query, category_ids: '139971', limit: PAGE_SIZE, offset: PAGE_SIZE * job.page,
    filter: 'conditionIds:{7000},buyingOptions:{AUCTION|FIXED_PRICE},deliveryCountry:HU,itemLocationCountry:'
      + job.state.country,
  };
  const query = Object.entries(params).map(([key, val]) => key + '=' + encodeURIComponent(val)).join('&');
  return fetchOptions({
    url: EBAY_ROOT + '/buy/browse/v1/item_summary/search?' + query, method: 'get', headers: browseHeaders(token),
  });
}

function applySearchPage(state, payload, checkedAt, secrets) {
  const items = payload.itemSummaries === undefined ? [] : payload.itemSummaries;
  if (!Number.isSafeInteger(payload.total) || payload.total < 0 || !Array.isArray(items)) {
    state.error = 'Az eBay keresési válasza hiányos vagy érvénytelen.';
    return false;
  }
  for (const item of items) {
    if (!record(item)) continue;
    if (!EU_COUNTRIES.includes(itemCountry(item))) {
      state.filteredNonEu++;
      continue;
    }
    const listing = normalizeListing(item, checkedAt, secrets);
    if (listing) state.listings.push(listing);
  }
  return true;
}

function searchEbay(countries, queries, clientSecrets, filters = {}) {
  const searchedAt = new Date();
  const states = countries.flatMap(country => queries.map(query => ({
    country, query, error: null, warnings: [], listings: [], filteredNonEu: 0, pagesRead: 0,
  })));
  let calls = 0;
  const countCall = (kind, count) => {
    dailyCounter(kind, count);
    calls += count;
  };
  const rawBatch = PropertiesService.getScriptProperties().getProperty('FETCH_BATCH_SIZE');
  const configuredBatch = Number(rawBatch);
  const batchSize = Number.isSafeInteger(configuredBatch) && configuredBatch > 0
    ? Math.min(configuredBatch, RUN_LIMIT) : 4;
  let credentials;
  let token;
  try {
    credentials = ebayCredentials();
    token = applicationToken(credentials, countCall);
  } catch (error) {
    if (!(error instanceof AppError)) throw error;
    for (const state of states) state.error = error.message;
  }

  const pending = token ? states.map(state => ({ state, page: 0, retry: false })) : [];
  const secrets = token ? [token, credentials.clientId, credentials.secret, ...clientSecrets] : clientSecrets;
  // First pages start in the queue before any retries or subsequent pages.
  while (pending.length && calls < RUN_LIMIT && Date.now() - searchedAt.getTime() < SEARCH_TIME_LIMIT_MS) {
    const batch = pending.splice(0, Math.min(batchSize, RUN_LIMIT - calls));
    const requests = batch.map(job => makeSearchRequest(job, token));
    try {
      countCall('browse', batch.length);
    } catch (error) {
      if (!(error instanceof AppError)) throw error;
      for (const job of [...batch, ...pending.splice(0)]) job.state.error = error.message;
      break;
    }
    let responses;
    try {
      responses = UrlFetchApp.fetchAll(requests);
    } catch {
      for (const job of batch) job.state.error = 'Hálózati hiba vagy időtúllépés az eBay keresési kötegében.';
      continue;
    }
    let retryQueued = false;
    for (const [index, job] of batch.entries()) {
      const { state, page, retry } = job;
      const response = responses[index];
      if (!response) {
        state.error = 'Hiányzik az eBay keresési válasza.';
        continue;
      }
      const status = response.getResponseCode();
      const payload = responseObject(response);
      if (payload.warnings !== undefined) {
        const identities = Array.isArray(payload.itemSummaries)
          ? payload.itemSummaries.flatMap(item => sellerIdentities(item?.seller)) : [];
        const warnings = safeWarning(payload.warnings, [...secrets, ...identities]);
        state.warnings.push(...(Array.isArray(warnings) ? warnings : [warnings]));
        Logger.log('eBay Browse (' + state.country + '): ' + JSON.stringify(warnings));
      }
      if (status === 429 && !retry) {
        pending.push({ state, page, retry: true });
        retryQueued = true;
      } else if (status === 429) {
        state.error = 'Az eBay korlátozta a hívásokat (HTTP 429).';
      } else if (status < 200 || status >= 300) {
        state.error = 'Az eBay keresése sikertelen (HTTP ' + status + ').';
      } else if (applySearchPage(state, payload, new Date(), secrets)) {
        state.pagesRead++;
        if ((page + 1) * PAGE_SIZE < payload.total) {
          if (page + 1 < PAGE_LIMIT) pending.push({ state, page: page + 1, retry: false });
          else {
            const warning = 'Az ország keresése elérte az ötoldalas korlátot.';
            state.warnings.push(warning);
            Logger.log('eBay Browse (' + state.country + '): ' + warning);
          }
        }
      }
    }
    if (retryQueued && calls < RUN_LIMIT) Utilities.sleep(1000);
  }
  const stopReason = calls >= RUN_LIMIT ? BUDGET_MESSAGE : 'A keresés elérte a futási időkorlátot.';
  for (const job of pending) job.state.error = stopReason;
  return collectSearchResults(states, searchedAt, new Date(), filters, calls, dailyCounter());
}

function effectivePrice(item) {
  return item.buying_options.includes('AUCTION') ? item.current_bid : item.price;
}

function matchesListing(item, filters) {
  const requiredOption = { auction: 'AUCTION', fixed: 'FIXED_PRICE' }[filters.buying_options];
  if (requiredOption && !item.buying_options.includes(requiredOption)) return false;
  const model = item.console_model;
  const family = model === 'PS5 Digital' ? 'PS5 (változat nem ismert)' : model.replace(/ (Disc|Digital)$/, '');
  if (filters.console_models?.length && !filters.console_models.some(value => [model, family].includes(value))) {
    return false;
  }
  const price = effectivePrice(item);
  if (filters.max_price != null && (price === null || Number(price) > filters.max_price)) return false;
  if (filters.max_total_price != null && item.shipping_cost !== null) {
    return item.total_price !== null && Number(item.total_price) <= filters.max_total_price;
  }
  return true;
}

function aggregateStatus(statuses) {
  if (statuses.every(status => status === 'error')) return 'error';
  return statuses.every(status => status === 'success') ? 'success' : 'partial';
}

function shippingBreakdown(items) {
  const totals = { auction: 0, fixed_price: 0 };
  const countries = {};
  for (const item of items) {
    const type = item.buying_options.includes('AUCTION') ? 'auction' : 'fixed_price';
    if (!countries[item.item_country]) countries[item.item_country] = { auction: 0, fixed_price: 0 };
    countries[item.item_country][type]++;
    totals[type]++;
  }
  return { by_buying_type: totals, by_country: countries };
}

function compareAmounts(left, right) {
  if (left === null) return right === null ? 0 : 1;
  return right === null ? -1 : Number(left) - Number(right);
}

function collectSearchResults(states, searchedAt, now, filters, calls, daily) {
  const byCountry = new Map();
  const unique = new Map();
  let filteredNonEu = 0;
  for (const state of states) {
    if (!byCountry.has(state.country)) byCountry.set(state.country, []);
    byCountry.get(state.country).push({
      query: state.query, status: state.error ? 'error' : 'success',
      error: state.error, warnings: state.warnings, count: state.listings.length,
    });
    filteredNonEu += state.filteredNonEu;
    for (const item of state.listings) {
      if (!EU_COUNTRIES.includes(item.item_country)) {
        filteredNonEu++;
        continue;
      }
      if (item.status !== 'ACTIVE' || (item.end_time && Date.parse(item.end_time) <= now.getTime())) continue;
      const key = item.source + ':' + item.source_listing_id;
      if (!unique.has(key)) unique.set(key, item);
    }
  }
  const countries = Array.from(byCountry, ([country, queries]) => ({
    country, status: aggregateStatus(queries.map(query => query.status)), queries,
  }));

  const typeCounts = Object.fromEntries(ITEM_TYPES.map(type => [type, 0]));
  const known = [];
  const unknown = [];
  for (const item of unique.values()) {
    typeCounts[item.item_type]++;
    if (['not_console', 'unsupported_model'].includes(item.item_type)) continue;
    if (item.item_type === 'mainboard' && !filters.include_mainboards) continue;
    if (!matchesListing(item, filters)) continue;
    (item.shipping_cost === null ? unknown : known).push(item);
  }
  known.sort((a, b) => compareAmounts(a.total_price, b.total_price));
  unknown.sort((a, b) => compareAmounts(effectivePrice(a), effectivePrice(b)));
  let status = aggregateStatus(countries.map(country => country.status));
  if (status === 'error' && states.some(state => state.pagesRead > 0)) status = 'partial';
  return {
    status, listings: known, unknown_shipping: unknown,
    unknown_shipping_breakdown: shippingBreakdown(unknown), countries, filtered_non_eu: filteredNonEu,
    item_type_counts: typeCounts, api_calls: calls, ...daily,
    quota_warning: daily.daily_browse_calls >= EBAY_DAILY_LIMIT * 0.9
      ? 'Az eBay napi Browse-kerete közel van a kimerüléshez.' : null,
    searched_at: searchedAt.toISOString(),
  };
}
