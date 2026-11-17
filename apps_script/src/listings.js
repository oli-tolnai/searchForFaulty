const EU_COUNTRIES = Object.freeze([
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE',
  'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE',
]);

function record(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function nonempty(value) {
  return typeof value === 'string' && value.trim() ? value : null;
}

function itemCountry(item) {
  const country = item.itemLocation?.country;
  return typeof country === 'string' && /^[a-z]{2}$/i.test(country) ? country.toUpperCase() : null;
}

function money(data) {
  const currency = nonempty(data?.currency);
  const value = String(data?.value ?? '');
  return currency && /^\d+(?:\.\d+)?$/.test(value) && Number.isFinite(Number(value))
    ? [value, currency] : [null, null];
}

function addMoney(left, right) {
  const [leftUnits, leftFraction = ''] = left.split('.');
  const [rightUnits, rightFraction = ''] = right.split('.');
  const scale = Math.max(leftFraction.length, rightFraction.length);
  const sum = BigInt(leftUnits + leftFraction.padEnd(scale, '0'))
    + BigInt(rightUnits + rightFraction.padEnd(scale, '0'));
  const digits = String(sum).padStart(scale + 1, '0');
  return scale ? digits.slice(0, -scale) + '.' + digits.slice(-scale) : digits;
}

function shipping(item) {
  if (Array.isArray(item.shippingOptions)) {
    for (const entry of item.shippingOptions) {
      if (!record(entry)) continue;
      const country = entry.shipToLocationUsedForEstimate?.country;
      if (country != null && country !== 'HU') continue;
      return entry.shippingCostType === 'CALCULATED' ? [null, null] : money(entry.shippingCost);
    }
  }
  return [null, null];
}

function timestamp(value) {
  if (typeof value !== 'string' || !/(?:Z|[+-]\d{2}:\d{2})$/.test(value)) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function unavailable(item) {
  const estimates = item.estimatedAvailabilities;
  return Array.isArray(estimates) && estimates.length > 0 && estimates.every(estimate =>
    ['OUT_OF_STOCK', 'TEMPORARILY_UNAVAILABLE'].includes(estimate?.estimatedAvailabilityStatus)
    || estimate?.estimatedAvailableQuantity === 0 || estimate?.estimatedRemainingQuantity === 0);
}

function normalizeListing(item, checkedAt, secrets = [], group = 'consoles') {
  const itemId = nonempty(item.itemId);
  const title = nonempty(item.title);
  const url = nonempty(item.itemWebUrl);
  if (!itemId || !title || !url) return null;

  const options = Array.isArray(item.buyingOptions)
    ? item.buyingOptions.filter(option => typeof option === 'string') : [];
  const auction = options.includes('AUCTION');
  const [amount, currency] = money(auction ? item.currentBidPrice : item.price);
  const [shippingCost, shippingCurrency] = shipping(item);
  const end = timestamp(item.itemEndDate);
  let status = 'ACTIVE';
  if ((end && Date.parse(end) <= checkedAt.getTime()) || (!auction && unavailable(item))) status = 'ENDED';
  else if ((!end && (auction || item.itemEndDate != null)) || !(auction || options.includes('FIXED_PRICE'))) {
    status = 'UNKNOWN';
  }

  const protectedValues = [...secrets, ...sellerIdentities(item.seller)];
  return {
    source: 'ebay', source_listing_id: itemId, title: redactContact(title, protectedValues),
    url: redactText(url, protectedValues),
    image_url: redactText(nonempty(item.image?.imageUrl), protectedValues),
    device_group: group, is_scuf: false,
    ...(group === 'controllers' ? classifyController(title) : classifyItem(title)),
    possibly_not_faulty: possiblyNotFaulty(title),
    buying_options: options,
    price: auction ? null : amount, current_bid: auction ? amount : null,
    bid_count: auction && Number.isInteger(item.bidCount) && item.bidCount >= 0 ? item.bidCount : null,
    currency, shipping_cost: shippingCost, shipping_currency: shippingCurrency,
    ships_to_hu: shippingCost === null ? 'unknown' : 'yes',
    total_price: amount !== null && shippingCost !== null && currency === shippingCurrency
      ? addMoney(amount, shippingCost) : null,
    item_country: itemCountry(item), end_time: end,
    listed_at: timestamp(item.itemCreationDate) || timestamp(item.itemOriginDate),
    condition: redactContact(nonempty(item.condition), protectedValues),
    status, last_checked_at: checkedAt.toISOString(), fault_source: 'condition',
  };
}
