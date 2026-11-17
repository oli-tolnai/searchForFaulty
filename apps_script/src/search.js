const PAGE_SIZE = 200;
const PAGE_LIMIT = 5;
const RUN_LIMIT = 59;
const SEARCH_TIME_LIMIT_MS = 300000;
const BUDGET_MESSAGE = 'A keresés elérte a futásonkénti híváskeretet.';
const ITEM_TYPES = [
  'console', 'console_bundle', 'mainboard', 'not_console', 'controller', 'controller_bundle',
  'not_controller', 'third_party', 'unsupported_model', 'needs_review',
];
const ACTIVE_ITEM_TYPES = ['console', 'console_bundle', 'controller', 'controller_bundle', 'needs_review'];

function makeSearchRequest(job, token) {
  const params = {
    q: job.state.query, category_ids: DEVICE_GROUPS[job.state.group].category, limit: PAGE_SIZE, offset: PAGE_SIZE * job.page,
    filter: 'conditionIds:{' + (job.state.conditions || ['7000']).join('|') +
      '},buyingOptions:{AUCTION|FIXED_PRICE},deliveryCountry:HU,itemLocationCountry:'
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
  if (state.total === undefined) state.total = payload.total;
  for (const item of items) {
    if (!record(item)) continue;
    if (!EU_COUNTRIES.includes(itemCountry(item))) {
      state.filteredNonEu++;
      continue;
    }
    if (state.faultWord && (!state.conditions.includes(String(item.conditionId)) ||
        !supplementaryFaultInTitle(item.title || '', state.faultWord, state.group))) {
      state.filteredNotFaulty++;
      continue;
    }
    const listing = normalizeListing(item, checkedAt, secrets, state.group);
    if (listing) {
      if (state.faultWord) listing.fault_source = 'title';
      state.listings.push(listing);
    }
  }
  return true;
}

function searchEbay(countries, queries, clientSecrets) {
  const searchedAt = new Date();
  const groupsByQuery = new Map(Object.entries(DEVICE_GROUPS).flatMap(([group, config]) =>
    config.queries.map(query => [query, group])));
  const states = countries.flatMap(country => queries.map(query => ({
    country, query, group: groupsByQuery.get(query), error: null, warnings: [], listings: [], filteredNonEu: 0, pagesRead: 0,
  })));
  const selectedGroups = [...new Set(queries.map(query => groupsByQuery.get(query)))];
  const supplementary = countries.flatMap(country => selectedGroups.flatMap(group =>
    (SUPPLEMENTARY_QUERIES[group]?.[country] || []).map(spec => ({
      country, query: spec.query, group, faultWord: spec.word, conditions: SUPPLEMENTARY_CONDITIONS[group],
      error: null, warnings: [], listings: [], filteredNonEu: 0, filteredNotFaulty: 0, pagesRead: 0,
    }))));
  states.push(...supplementary);
  const runLimit = Math.max(RUN_LIMIT + supplementary.length, states.length + 5);
  let calls = 0;
  let oauthCalls = 0;
  const countCall = (kind, count) => {
    dailyCounter(kind, count);
    calls += count;
    if (kind === 'oauth') oauthCalls += count;
  };
  const batchSize = ebayFetchBatchSize();
  let credentials;
  let token;
  try {
    credentials = ebayCredentials();
    token = applicationToken(credentials, countCall);
  } catch (error) {
    if (!(error instanceof AppError)) throw error;
    for (const state of states) {
      state.error = error.message;
      state.errorCode = error.code;
    }
  }

  const pending = token ? states.map(state => ({ state, page: 0, retry: false })) : [];
  const secrets = token ? [token, credentials.clientId, credentials.secret, ...clientSecrets] : clientSecrets;
  // First pages start in the queue before any retries or subsequent pages.
  while (pending.length && calls < runLimit && Date.now() - searchedAt.getTime() < SEARCH_TIME_LIMIT_MS) {
    const batch = pending.splice(0, Math.min(batchSize, runLimit - calls));
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
    if (retryQueued && calls < runLimit) Utilities.sleep(1000);
  }
  const stopReason = calls >= runLimit ? BUDGET_MESSAGE : 'A keresés elérte a futási időkorlátot.';
  for (const job of pending) job.state.error = stopReason;
  return collectSearchResults(states, searchedAt, new Date(), items => {
    const browseSearchCalls = calls - oauthCalls;
    const shipping = checkHungarianShipping(items, token, batchSize, countCall,
      searchedAt.getTime() + SEARCH_TIME_LIMIT_MS, secrets);
    return { ...shipping, api_calls: calls, browse_search_calls: browseSearchCalls, oauth_calls: oauthCalls, ...dailyCounter() };
  });
}

function effectivePrice(item) {
  return item.buying_options.includes('AUCTION') ? item.current_bid : item.price;
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

function collectSearchResults(states, searchedAt, now, enrich) {
  const byCountry = new Map();
  const unique = new Map();
  let filteredNonEu = 0;
  for (const state of states) {
    if (!byCountry.has(state.country)) byCountry.set(state.country, []);
    byCountry.get(state.country).push({
      query: state.query, device_group: state.group, fault_source: state.faultWord ? 'title' : 'condition',
      status: state.error ? 'error' : 'success',
      error: state.error, warnings: state.warnings, count: state.listings.length,
      total: state.total ?? null, filtered_not_faulty: state.filteredNotFaulty || 0,
      ...(state.errorCode ? { error_code: state.errorCode } : {}),
    });
    filteredNonEu += state.filteredNonEu;
    for (const item of state.listings) {
      if (!EU_COUNTRIES.includes(item.item_country)) {
        filteredNonEu++;
        continue;
      }
      if (item.status !== 'ACTIVE' || (item.end_time && Date.parse(item.end_time) <= now.getTime())) continue;
      const key = item.source + ':' + item.source_listing_id;
      const previous = unique.get(key);
      const recognized = type => ['console', 'console_bundle', 'controller', 'controller_bundle'].includes(type);
      if (!previous || (previous.fault_source !== item.fault_source
        ? item.fault_source === 'condition'
        : previous.device_group === item.device_group
        ? previous.shipping_cost === null && item.shipping_cost !== null
        : !recognized(previous.item_type) && recognized(item.item_type))) {
        unique.set(key, item);
      }
    }
  }
  const countries = Array.from(byCountry, ([country, queries]) => ({
    country, status: aggregateStatus(queries.map(query => query.status)), queries,
  }));

  const typeCounts = Object.fromEntries(ITEM_TYPES.map(type => [type, 0]));
  const known = [];
  const unknown = [];
  const stats = enrich(Array.from(unique.values()));
  for (const item of unique.values()) {
    if (item.end_time && Date.parse(item.end_time) <= Date.now()) continue;
    typeCounts[item.item_type]++;
    (item.shipping_cost === null ? unknown : known).push(item);
  }
  known.sort((a, b) => compareAmounts(a.total_price, b.total_price));
  unknown.sort((a, b) => compareAmounts(effectivePrice(a), effectivePrice(b)));
  let status = aggregateStatus(countries.map(country => country.status));
  if (status === 'error' && states.some(state => state.pagesRead > 0)) status = 'partial';
  return {
    status, listings: known, unknown_shipping: unknown,
    unknown_shipping_breakdown: shippingBreakdown(unknown), countries, filtered_non_eu: filteredNonEu,
    filtered_not_faulty: states.reduce((sum, state) => sum + (state.filteredNotFaulty || 0), 0),
    item_type_counts: typeCounts, ...stats,
    quota_warning: stats.daily_browse_calls >= EBAY_DAILY_LIMIT * 0.9
      ? 'Az eBay napi Browse-kerete közel van a kimerüléshez.' : null,
    searched_at: searchedAt.toISOString(),
  };
}
