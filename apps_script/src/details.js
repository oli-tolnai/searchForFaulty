const HTML_ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ',
  ndash: '–', mdash: '—', euro: '€', auml: 'ä', ouml: 'ö', uuml: 'ü', szlig: 'ß',
  Auml: 'Ä', Ouml: 'Ö', Uuml: 'Ü', eacute: 'é', Eacute: 'É', egrave: 'è', aacute: 'á',
};

function plainDescription(html) {
  if (typeof html !== 'string') return null;
  const text = html
    .replace(/<!--[\s\S]*?(?:-->|$)/g, '')
    .replace(/<(script|style|iframe)\b(?:"[^"]*"|'[^']*'|[^'">])*>[\s\S]*?(?:<\/\1\s*>|$)/gi, '')
    .replace(/<\/?(?:p|div|br|li|ul|ol|tr|td|h[1-6]|section)\b(?:"[^"]*"|'[^']*'|[^'">])*>/gi, '\n')
    .replace(/<\/?[a-z!?](?:"[^"]*"|'[^']*'|[^'">])*>/gi, '')
    .replace(/&(#(?:x[0-9a-f]+|\d+)|[a-z]+);/gi, (entity, code) => {
      if (code[0] !== '#') return Object.prototype.hasOwnProperty.call(HTML_ENTITIES, code) ? HTML_ENTITIES[code] : entity;
      const point = code[1].toLowerCase() === 'x' ? parseInt(code.slice(2), 16) : Number(code.slice(1));
      return point > 0 && point <= 0x10FFFF && !(point >= 0xD800 && point <= 0xDFFF)
        ? String.fromCodePoint(point) : '\uFFFD';
    })
    .replace(/[^\S\r\n]+/g, ' ')
    .replace(/\s*\n\s*/g, '\n')
    .trim();
  return text || null;
}

function safeDescription(html, secrets) {
  const text = redactContact(plainDescription(html), secrets);
  return text ? Array.from(text).slice(0, 8000).join('') : null;
}

function listingDetails(itemId, clientSecrets) {
  const cache = CacheService.getScriptCache();
  const key = 'ebay:details:' + itemId;
  const cached = cache.get(key);
  if (cached) {
    const saved = JSON.parse(cached);
    if (saved.ships_to_hu !== undefined) return saved;
  }
  const credentials = ebayCredentials();
  const token = applicationToken(credentials, dailyCounter);
  const url = EBAY_ROOT + '/buy/browse/v1/item/' + encodeURIComponent(itemId);
  const countAndFetch = () => {
    dailyCounter('browse', 1);
    return fetchEbay(url, { method: 'get', headers: browseHeaders(token) });
  };
  let response = countAndFetch();
  if (response.getResponseCode() === 429) {
    Utilities.sleep(1000);
    response = countAndFetch();
  }
  const status = response.getResponseCode();
  const item = responseObject(response);
  const secrets = [token, credentials.clientId, credentials.secret, ...clientSecrets, ...sellerIdentities(item.seller)];
  if (item.warnings !== undefined) {
    Logger.log('eBay getItem: ' + JSON.stringify(safeWarning(item.warnings, secrets)));
  }
  if (status === 404) throw new AppError('listing_not_found', 'A hirdetés már nem érhető el.');
  if (status < 200 || status >= 300) {
    throw new AppError('ebay_details', 'A hirdetés lekérése sikertelen (HTTP ' + status + ').');
  }
  if (item.itemId !== itemId) throw new AppError('ebay_details', 'Az eBay hirdetésválasza érvénytelen.');
  const end = timestamp(item.itemEndDate);
  const remaining = end ? Date.parse(end) - Date.now() : Infinity;
  if (remaining <= 0 || unavailable(item)) {
    throw new AppError('listing_not_found', 'A hirdetés már nem érhető el.');
  }

  const shippingInfo = shippingFromDetail(item);
  cache.put('ebay:ship-hu:' + itemId, JSON.stringify(shippingInfo), SHIPPING_CACHE_SECONDS);
  const phoneText = [item.title, item.conditionDescription, plainDescription(item.description)].filter(Boolean).join(' ');
  const cloudStatus = iphoneCloudStatus(phoneText);
  cache.put('ebay:icloud:' + itemId, cloudStatus, SHIPPING_CACHE_SECONDS);
  const details = {
    ...shippingInfo,
    icloud_status: cloudStatus,
    condition_description: safeDescription(item.conditionDescription, secrets),
    short_description: safeDescription(item.shortDescription, secrets),
    description_text: safeDescription(item.description, secrets),
  };
  const serialized = JSON.stringify(details);
  const ttl = Math.min(3600, Math.floor(remaining / 1000));
  if (ttl > 0 && Utilities.newBlob(serialized).getBytes().length <= 100 * 1024) cache.put(key, serialized, ttl);
  return details;
}
