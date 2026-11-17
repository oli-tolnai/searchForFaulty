const HU_REGIONS = new Set(['HU', 'EUROPE', 'EUROPEAN_UNION', 'WORLDWIDE']);
const SHIPPING_CACHE_SECONDS = 21600;

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

function applyCachedHungarianShipping(items) {
  const cache = CacheService.getScriptCache();
  const cloudKeys = items.filter(item => item.device_group === 'iphone').map(item => 'ebay:icloud:' + item.source_listing_id);
  const cloud = cloudKeys.length ? cache.getAll(cloudKeys) : {};
  for (const item of items.filter(item => item.device_group === 'iphone')) {
    const saved = cloud['ebay:icloud:' + item.source_listing_id];
    if (saved === 'locked') {
      item.icloud_status = 'locked';
      if (['phone', 'phone_bundle', 'needs_review'].includes(item.item_type)) item.item_type = 'icloud_locked';
    } else if (saved === 'free_by_seller' && item.icloud_status !== 'locked') item.icloud_status = saved;
  }
  const unknown = items.filter(item => item.shipping_cost === null);
  const keys = unknown.map(item => 'ebay:ship-hu:' + item.source_listing_id);
  const cached = keys.length ? cache.getAll(keys) : {};
  const outcomes = { yes: 0, no: 0, unknown: 0, probably_no: 0 };
  for (const [index, item] of unknown.entries()) {
    let saved;
    try { saved = cached[keys[index]] ? JSON.parse(cached[keys[index]]) : null; } catch { saved = null; }
    if (saved && ['yes', 'no'].includes(saved.ships_to_hu)) {
      const [cost, currency] = saved.ships_to_hu === 'no' ? [null, null]
        : money({ value: saved.shipping_cost, currency: saved.shipping_currency });
      Object.assign(item, { ships_to_hu: saved.ships_to_hu, shipping_cost: cost, shipping_currency: currency });
    } else item.ships_to_hu = 'probably_no';
    const price = effectivePrice(item);
    item.total_price = price !== null && item.shipping_cost !== null && item.currency === item.shipping_currency
      ? addMoney(price, item.shipping_cost) : null;
    outcomes[item.ships_to_hu]++;
  }
  return { get_item_calls: 0, shipping_check: { initial_unknown: unknown.length, ...outcomes, failed: 0 } };
}
