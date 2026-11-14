const BENCH_COUNTRIES = 'AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE'.split(' ');
const BENCH_QUERIES = ['ps5', 'xbox series'];
const BENCH_PAGE_SIZE = 200;
const BENCH_EXTRA_PAGES = 4;
const BENCH_BATCH_SIZE = 4;
const BENCH_RUN_MS = 125000;

function runEbayBenchmark() {
  const properties = PropertiesService.getScriptProperties();
  const clientId = (properties.getProperty('EBAY_CLIENT_ID') || '').trim();
  const clientSecret = (properties.getProperty('EBAY_CLIENT_SECRET') || '').trim();
  if (!clientId || !clientSecret) {
    console.log('Hiányzik az EBAY_CLIENT_ID vagy az EBAY_CLIENT_SECRET Script Property.');
    return;
  }

  let token;
  try {
    const response = UrlFetchApp.fetch('https://api.ebay.com/identity/v1/oauth2/token', {
      method: 'post',
      headers: { Authorization: 'Basic ' + Utilities.base64Encode(clientId + ':' + clientSecret) },
      payload: { grant_type: 'client_credentials', scope: 'https://api.ebay.com/oauth/api_scope' },
      followRedirects: false,
      muteHttpExceptions: true,
      timeoutSeconds: 15,
    });
    const status = response.getResponseCode();
    if (status !== 200) {
      console.log('OAuth: HTTP ' + status + '. Browse-hívás nem indult.');
      return;
    }
    token = JSON.parse(response.getContentText()).access_token;
  } catch (_) {
    console.log('OAuth: hálózati vagy válaszfeldolgozási hiba.');
    return;
  }
  if (typeof token !== 'string' || !token) {
    console.log('OAuth: hiányzó alkalmazástoken.');
    return;
  }

  const initial = BENCH_COUNTRIES.flatMap(country =>
    BENCH_QUERIES.map(query => ({ country, query, offset: 0 }))
  );
  console.log('OAuth: sikeres, 1 kérés. A két mérés ugyanazt a tokent használja.');
  benchmarkMode(initial, token, false);
  benchmarkMode(initial, token, true);
}

function benchmarkRequest(page, token) {
  const filter = 'conditionIds:{7000},buyingOptions:{AUCTION|FIXED_PRICE},deliveryCountry:HU,itemLocationCountry:' + page.country;
  const query = {
    q: page.query, category_ids: '139971', filter, limit: BENCH_PAGE_SIZE, offset: page.offset,
  };
  const url = 'https://api.ebay.com/buy/browse/v1/item_summary/search?' +
    Object.keys(query).map(key => key + '=' + encodeURIComponent(query[key])).join('&');
  return {
    url,
    method: 'get',
    headers: {
      Authorization: 'Bearer ' + token,
      'X-EBAY-C-MARKETPLACE-ID': 'EBAY_DE',
      'X-EBAY-C-ENDUSERCTX': 'contextualLocation=country%3DHU',
    },
    followRedirects: false,
    muteHttpExceptions: true,
    timeoutSeconds: 10,
  };
}

function benchmarkMode(initial, token, parallel) {
  const started = Date.now();
  const queue = initial.slice();
  let ok = 0;
  let failed = 0;
  let batchErrors = 0;
  let extraPages = 0;
  let truncated = 0;
  let rows = 0;
  const euIds = new Set();
  const statusCodes = {};
  const warningCodes = {};
  const batchSize = parallel ? BENCH_BATCH_SIZE : 1;
  while (queue.length && Date.now() - started < BENCH_RUN_MS) {
    const batch = queue.splice(0, batchSize);
    const requests = batch.map(page => benchmarkRequest(page, token));
    let responses;
    try {
      if (parallel) {
        responses = UrlFetchApp.fetchAll(requests);
      } else {
        const { url, ...options } = requests[0];
        responses = [UrlFetchApp.fetch(url, options)];
      }
    } catch (_) {
      failed += batch.length;
      if (parallel) batchErrors++;
      continue;
    }
    for (let index = 0; index < batch.length; index++) {
      const page = batch[index];
      try {
        const response = responses[index];
        const status = response.getResponseCode();
        statusCodes[status] = (statusCodes[status] || 0) + 1;
        if (status < 200 || status >= 300) {
          failed++;
          continue;
        }
        const payload = JSON.parse(response.getContentText());
        const items = payload.itemSummaries ?? [];
        if (!Number.isInteger(payload.total) || payload.total < 0 || !Array.isArray(items)) {
          failed++;
          continue;
        }
        ok++;
        rows += items.length;
        for (const item of items) {
          if (item && BENCH_COUNTRIES.includes(item.itemLocation?.country) && typeof item.itemId === 'string' && item.itemId) {
            euIds.add(item.itemId);
          }
        }
        if (Array.isArray(payload.warnings)) {
          for (const warning of payload.warnings) {
            if (Number.isInteger(warning?.errorId)) {
              const id = warning.errorId;
              warningCodes[id] = (warningCodes[id] || 0) + 1;
            }
          }
        }
        if (page.offset + BENCH_PAGE_SIZE < payload.total) {
          if (extraPages < BENCH_EXTRA_PAGES && page.offset < 4 * BENCH_PAGE_SIZE) {
            extraPages++;
            queue.push({ ...page, offset: page.offset + BENCH_PAGE_SIZE });
          } else {
            truncated++;
          }
        }
      } catch (_) {
        failed++;
      }
    }
  }

  console.log(JSON.stringify({
    modoszat: parallel ? 'fetchAll (legfeljebb 4 egyszerre)' : 'fetch (soros)',
    ido_ms: Date.now() - started,
    sikeres: ok,
    hibas_vagy_valasz_nelkuli: failed,
    fetchAll_kivetelek: batchErrors,
    el_nem_inditott_oldalak: queue.length,
    lapozasi_korlatot_elero_keresesek: truncated,
    visszakapott_tetelek: rows,
    egyedi_eu_tetelek: euIds.size,
    http_statuszok: statusCodes,
    warning_kodok: warningCodes,
  }));
}
