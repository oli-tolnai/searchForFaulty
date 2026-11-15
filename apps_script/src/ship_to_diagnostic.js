const HU_SHIPPING_REGIONS = new Set(['HU', 'EUROPE', 'EUROPEAN_UNION', 'WORLDWIDE']);
const BULK_ITEM_SCOPE = 'https://api.ebay.com/oauth/api_scope/buy.item.bulk';

function shipToRegionIds(regions) {
  if (!Array.isArray(regions)) return [];
  return regions.map(region => region?.regionId)
    .filter(id => typeof id === 'string' && /^[A-Z_]{2,40}$/i.test(id))
    .map(id => id.toUpperCase());
}

function shippingDiagnosticOptions(options, secrets) {
  if (!Array.isArray(options)) return null;
  return options.filter(record).map(option => {
    const projected = {};
    for (const key of ['shippingCost', 'additionalShippingCostPerUnit', 'importCharges']) {
      const [value, currency] = money(option[key]);
      if (value !== null && /^[A-Z]{3}$/.test(currency)) projected[key] = { value, currency };
    }
    for (const key of ['shippingCostType', 'shippingServiceCode', 'shippingCarrierCode', 'type']) {
      if (typeof option[key] === 'string') projected[key] = redactContact(option[key], secrets);
    }
    for (const key of ['minEstimatedDeliveryDate', 'maxEstimatedDeliveryDate']) {
      const value = timestamp(option[key]);
      if (value) projected[key] = value;
    }
    const country = option.shipToLocationUsedForEstimate?.country;
    if (typeof country === 'string' && /^[A-Z]{2}$/.test(country)) {
      projected.shipToLocationUsedForEstimate = { country };
    }
    return projected;
  });
}

function shippingDiagnosticObservation(item, secrets) {
  const protectedValues = [...secrets, ...sellerIdentities(item?.seller)];
  const locations = item?.shipToLocations;
  const included = shipToRegionIds(locations?.regionIncluded);
  const excluded = shipToRegionIds(locations?.regionExcluded);
  let classification = 'nem eldönthető';
  if (excluded.some(id => HU_SHIPPING_REGIONS.has(id))) classification = 'kizárja HU-t';
  else if (included.some(id => HU_SHIPPING_REGIONS.has(id))) classification = 'beleérti HU-t';
  return {
    regionIncluded: included.map(id => redactText(id, protectedValues)),
    regionExcluded: excluded.map(id => redactText(id, protectedValues)),
    shippingOptions: shippingDiagnosticOptions(item?.shippingOptions, protectedValues),
    classification,
  };
}

function shippingDiagnosticRequest(url, options, kind, counts, key) {
  dailyCounter(kind, 1);
  counts[key]++;
  const response = fetchEbay(url, options);
  const payload = responseObject(response);
  const status = response.getResponseCode();
  if (status < 200 || status >= 300) {
    const ids = Array.isArray(payload.errors)
      ? payload.errors.map(error => error?.errorId).filter(Number.isSafeInteger) : [];
    const oauthCode = ['invalid_scope', 'invalid_client', 'unauthorized_client', 'invalid_request',
      'invalid_grant', 'unsupported_grant_type', 'temporarily_unavailable'].includes(payload.error)
      ? ', ' + payload.error : '';
    throw new AppError('shipping_probe_http', 'HTTP ' + status + oauthCode
      + (ids.length ? ', eBay hibakód: ' + ids.join(', ') : ''));
  }
  return payload;
}

function diagnoseShipToLocations() {
  const counts = { search: 0, oauth: 0, getItems: 0, getItem: 0 };
  const classification = { 'kizárja HU-t': 0, 'beleérti HU-t': 0, 'nem eldönthető': 0 };
  const listed = new Map();
  let validBulkResponses = 0;
  let bulkFieldCount = 0;
  const clientSecrets = (PropertiesService.getScriptProperties().getProperty('CLIENT_TOKENS') || '')
    .split(',').map(value => value.trim()).filter(Boolean);
  try {
    const result = searchEbay(EU_COUNTRIES, QUERIES, clientSecrets, { include_mainboards: true });
    counts.search = result.api_calls;
    const listings = result.unknown_shipping;
    Logger.log('Keresés állapota: ' + result.status + ' | Ismeretlen szállítású tételek: ' + listings.length);
    if (result.status !== 'success') {
      const errors = result.countries.flatMap(country => country.queries.map(query => query.error)).filter(Boolean);
      for (const error of new Set(errors)) Logger.log('Keresési hiba: ' + error);
    }
    if (!listings.length) return;

    const credentials = ebayCredentials();
    const secrets = [...clientSecrets, credentials.clientId, credentials.secret,
      CacheService.getScriptCache().get(OAUTH_CACHE_KEY)];
    let fallback = false;
    try {
      const options = oauthRequestOptions(Utilities.base64Encode(credentials.clientId + ':' + credentials.secret));
      options.payload.scope = BULK_ITEM_SCOPE;
      const token = shippingDiagnosticRequest(OAUTH_URL, options, 'oauth', counts, 'oauth').access_token;
      if (!nonempty(token)) throw new AppError('shipping_probe_oauth', 'Az OAuth-válaszban nincs bulk token.');
      secrets.push(token);
      for (let index = 0; index < listings.length; index += 20) {
        const ids = listings.slice(index, index + 20).map(item => item.source_listing_id);
        const data = shippingDiagnosticRequest(EBAY_ROOT + '/buy/browse/v1/item/?item_ids='
          + ids.map(encodeURIComponent).join(','), { method: 'get', headers: browseHeaders(token) },
        'browse', counts, 'getItems');
        if (!Array.isArray(data.items)) {
          throw new AppError('shipping_probe_payload', 'A getItems válaszában nincs items tömb.');
        }
        validBulkResponses++;
        for (const item of data.items) {
          if (!record(item) || !ids.includes(item.itemId)) continue;
          if (Object.prototype.hasOwnProperty.call(item, 'shipToLocations')) bulkFieldCount++;
          listed.set(item.itemId, item);
        }
      }
    } catch (error) {
      if (!(error instanceof AppError)) throw error;
      Logger.log('getItems nem érhető el vagy megszakadt: ' + error.message);
      fallback = true;
    }

    if (fallback || !Array.from(listed.values()).some(item => record(item.shipToLocations))) {
      Logger.log('getItem tartalékmérés az első ' + Math.min(10, listings.length) + ' tételre.');
      try {
        const token = applicationToken(credentials, (kind, count) => {
          dailyCounter(kind, count);
          counts.oauth += count;
        });
        secrets.push(token);
        for (const [index, listing] of listings.slice(0, 10).entries()) {
          const id = listing.source_listing_id;
          try {
            const item = shippingDiagnosticRequest(EBAY_ROOT + '/buy/browse/v1/item/' + encodeURIComponent(id),
              { method: 'get', headers: browseHeaders(token) }, 'browse', counts, 'getItem');
            if (item.itemId !== id) {
              throw new AppError('shipping_probe_payload', 'A getItem válaszában nem a kért tétel szerepel.');
            }
            listed.set(id, item);
          } catch (error) {
            if (!(error instanceof AppError)) throw error;
            Logger.log('getItem, ' + (index + 1) + '. tétel: ' + error.message);
          }
        }
      } catch (error) {
        if (!(error instanceof AppError)) throw error;
        Logger.log('A getItem tartalékmérés nem indult el: ' + error.message);
      }
    }

    for (const listing of listings) {
      const item = listed.get(listing.source_listing_id);
      const observation = shippingDiagnosticObservation(item, secrets);
      const title = redactContact(listing.title, [...secrets, ...sellerIdentities(item?.seller)]);
      classification[observation.classification]++;
      Logger.log(JSON.stringify({
        title: Array.from(title).slice(0, 50).join(''), country: listing.item_country,
        ...observation, ...(item ? {} : { megjegyzés: 'Nem sikerült lekérni vagy kívül esett a mintán.' }),
      }));
    }
  } catch (error) {
    Logger.log(error instanceof AppError ? error.message : 'Váratlan diagnosztikai hiba.');
  } finally {
    const fieldStatus = bulkFieldCount > 0 ? 'igen, ' + bulkFieldCount + ' tételnél'
      : validBulkResponses ? 'nem' : 'nem ellenőrizhető (nincs használható getItems-válasz)';
    Logger.log('shipToLocations a getItems válaszában: ' + fieldStatus);
    Logger.log('Besorolás: ' + JSON.stringify(classification) + ' | Lekért tételek: ' + listed.size);
    Logger.log('API-hívások: ' + Object.values(counts).reduce((sum, count) => sum + count, 0)
      + ' | keresés: ' + counts.search + ', további OAuth: ' + counts.oauth
      + ', getItems: ' + counts.getItems + ', getItem: ' + counts.getItem);
  }
}
