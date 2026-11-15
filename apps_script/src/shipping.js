const HU_REGIONS = new Set(['HU', 'EUROPE', 'EUROPEAN_UNION', 'WORLDWIDE']);
const SHIPPING_CACHE_SECONDS = 21600;
const MAX_GET_ITEM_CALLS = 60;

function shipsToHungary(locations) {
  const includesHu = regions => Array.isArray(regions) && regions.some(region =>
    HU_REGIONS.has(typeof region?.regionId === 'string' ? region.regionId.trim().toUpperCase() : ''));
  if (includesHu(locations?.regionExcluded)) return 'no';
  const included = Array.isArray(locations?.regionIncluded)
    ? locations.regionIncluded.filter(region => nonempty(region?.regionId)) : [];
  if (includesHu(included)) return 'yes';
  return included.length ? 'no' : 'unknown';
}

function shippingFromDetail(item) {
  const shipsToHu = shipsToHungary(item.shipToLocations);
  let cost = null;
  let currency = null;
  if (shipsToHu !== 'no' && Array.isArray(item.shippingOptions)) {
    for (const option of item.shippingOptions) {
      if (!record(option)) continue;
      const country = option.shipToLocationUsedForEstimate?.country;
      // An unlabeled quote is usable only when the item is known to ship to HU.
      if (country !== 'HU' && !(country == null && shipsToHu === 'yes')) continue;
      if (option.shippingCostType === 'CALCULATED') continue;
      [cost, currency] = money(option.shippingCost);
      if (cost !== null) break;
    }
  }
  return { ships_to_hu: shipsToHu, shipping_cost: cost, shipping_currency: currency };
}

function checkHungarianShipping(items, token, batchSize, countCall, deadline, secrets) {
  const cache = CacheService.getScriptCache();
  const unknown = items.filter(item => item.shipping_cost === null);
  const keys = unknown.map(item => 'ebay:ship-hu:' + item.source_listing_id);
  const cached = keys.length ? cache.getAll(keys) : {};
  const pending = [];
  const apply = (item, shipping) => {
    Object.assign(item, shipping);
    const price = effectivePrice(item);
    if (price !== null && item.shipping_cost !== null && item.currency === item.shipping_currency) {
      item.total_price = addMoney(price, item.shipping_cost);
    }
  };
  for (const [index, item] of unknown.entries()) {
    const key = keys[index];
    if (cached[key]) apply(item, JSON.parse(cached[key]));
    else pending.push({ item, key });
  }
  let calls = 0;
  let failed = 0;
  const toCheck = pending.slice(0, MAX_GET_ITEM_CALLS);
  for (let offset = 0; offset < toCheck.length && Date.now() < deadline; offset += batchSize) {
    const batch = toCheck.slice(offset, offset + batchSize);
    try {
      countCall('browse', batch.length);
    } catch (error) {
      if (!(error instanceof AppError)) throw error;
      Logger.log('Szállítás ellenőrzése: ' + error.message);
      break;
    }
    calls += batch.length;
    let responses;
    try {
      responses = UrlFetchApp.fetchAll(batch.map(({ item }) => fetchOptions({
        url: EBAY_ROOT + '/buy/browse/v1/item/' + encodeURIComponent(item.source_listing_id),
        method: 'get', headers: browseHeaders(token),
      })));
    } catch {
      failed += batch.length;
      continue;
    }
    const updates = {};
    for (const [index, { item, key }] of batch.entries()) {
      const response = responses[index];
      const data = response ? responseObject(response) : {};
      if (data.warnings !== undefined) {
        Logger.log('eBay getItem: ' + JSON.stringify(safeWarning(data.warnings, [...secrets, ...sellerIdentities(data.seller)])));
      }
      if (response?.getResponseCode() !== 200 || data.itemId !== item.source_listing_id) {
        failed++;
        continue;
      }
      const shipping = shippingFromDetail(data);
      apply(item, shipping);
      updates[key] = JSON.stringify(shipping);
    }
    if (Object.keys(updates).length) cache.putAll(updates, SHIPPING_CACHE_SECONDS);
  }
  const outcomes = { yes: 0, no: 0, unknown: 0 };
  for (const item of unknown) outcomes[item.ships_to_hu]++;
  return { get_item_calls: calls, shipping_check: { initial_unknown: unknown.length, ...outcomes, failed } };
}
