function alertDefaults(row) {
  const models = row.models || [];
  const inferredGroups = Object.keys(DEVICE_GROUPS).filter(group =>
    !models.length || models.some(model => DEVICE_GROUPS[group].models.includes(model)));
  return {
    name: 'Értesítési szabály', device_groups: inferredGroups, buying_options: 'both',
    max_price: null, max_total_price: null, known_shipping_only: !row.include_unknown_shipping,
    ending_hours: null, include_keywords: [], exclude_keywords: [], countries: [],
    exclude_possibly_not_faulty: true, exclude_banned: false, include_title_faults: true,
    ...Object.fromEntries(Object.entries(row).filter(([, value]) => value !== undefined)),
  };
}

function alertValues(input, secrets = []) {
  const row = alertDefaults(input);
  const list = (values, allowed, max) => Array.isArray(values) && values.length <= max &&
    values.every(value => allowed.includes(value));
  const models = configuredModels();
  const keywordList = values => Array.isArray(values) && values.length <= 20 &&
    values.every(value => typeof value === 'string' && value.trim().length > 0 && value.length <= 100);
  if (!nonempty(row.name) || row.name.length > 120 ||
      !list(row.device_groups, Object.keys(DEVICE_GROUPS), Object.keys(DEVICE_GROUPS).length) ||
      !row.device_groups.length || !list(row.models, models, models.length) ||
      !list(row.countries, EU_COUNTRIES, EU_COUNTRIES.length) ||
      !['both', 'auction', 'fixed'].includes(row.buying_options) ||
      ![null, 6, 12, 24, 48].includes(row.ending_hours) ||
      [row.max_price, row.max_total_price].some(value => value !== null && !notificationPrice(value)) ||
      !keywordList(row.include_keywords) || !keywordList(row.exclude_keywords) ||
      ['known_shipping_only', 'exclude_possibly_not_faulty', 'exclude_banned', 'include_title_faults', 'enabled']
        .some(key => typeof row[key] !== 'boolean')) invalidState();
  const safe = { ...row, name: redactContact(row.name.trim(), secrets),
    include_keywords: row.include_keywords.map(word => redactContact(word.trim(), secrets)),
    exclude_keywords: row.exclude_keywords.map(word => redactContact(word.trim(), secrets)),
    include_unknown_shipping: !row.known_shipping_only };
  return Object.fromEntries(STATE_COLUMNS.alerts.filter(key => Object.prototype.hasOwnProperty.call(safe, key))
    .map(key => [key, safe[key]]));
}

function alertMatches(item, original, now = new Date()) {
  const rule = alertDefaults(original);
  const group = item.device_group || 'consoles';
  if (!rule.enabled || item.status !== 'ACTIVE' || !ACTIVE_ITEM_TYPES.includes(item.item_type) || item.ships_to_hu === 'no' ||
      !rule.device_groups.includes(group) || item.currency !== 'EUR') return false;
  if (rule.models.length && !rule.models.includes(listingModelFamily(item.console_model))) return false;
  if (rule.countries.length && !rule.countries.includes(item.item_country)) return false;
  if (rule.exclude_possibly_not_faulty && item.possibly_not_faulty) return false;
  if (rule.exclude_banned && item.is_banned) return false;
  if (!rule.include_title_faults && item.fault_source === 'title') return false;
  const auction = item.buying_options.includes('AUCTION');
  if (rule.buying_options === 'auction' && !auction) return false;
  if (rule.buying_options === 'fixed' && !item.buying_options.includes('FIXED_PRICE')) return false;
  if (auction) {
    const end = Date.parse(item.end_time);
    if (!Number.isFinite(end) || end <= now.getTime()) return false;
    if (rule.ending_hours !== null && end - now.getTime() > rule.ending_hours * 3600000) return false;
  }
  const title = item.title.toLowerCase();
  if (rule.include_keywords.length && !rule.include_keywords.some(word => title.includes(word.toLowerCase()))) return false;
  if (rule.exclude_keywords.some(word => title.includes(word.toLowerCase()))) return false;
  const price = effectivePrice(item);
  if (rule.max_price !== null && (price === null || Number(price) > rule.max_price)) return false;
  const unknown = item.shipping_cost === null || item.total_price === null || item.ships_to_hu === 'unknown';
  if (rule.known_shipping_only && unknown) return false;
  if (rule.max_total_price !== null &&
      (unknown ? price === null || Number(price) > rule.max_total_price : Number(item.total_price) > rule.max_total_price)) return false;
  return true;
}
