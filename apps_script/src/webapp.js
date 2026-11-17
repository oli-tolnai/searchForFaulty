const API_VERSION = '1.0.0';
const BODY_LIMIT = 10 * 1024;

function jsonOutput(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}

function validToken(token, configuredTokens) {
  if (typeof token !== 'string' || !token || !configuredTokens.length) return false;
  const digest = value => Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, value, Utilities.Charset.UTF_8);
  const actual = digest(token);
  let matched = 0;
  for (const configured of configuredTokens) {
    const expected = digest(configured);
    let different = 0;
    for (let index = 0; index < expected.length; index++) different |= actual[index] ^ expected[index];
    matched |= Number(different === 0);
  }
  return matched === 1;
}

function searchValues(input, allowed) {
  if (input === undefined) return allowed;
  if (!Array.isArray(input) || !input.length || input.some(value => !allowed.includes(value))) {
    throw new AppError('invalid_params', 'A keresés ország- vagy kulcsszólistája érvénytelen.');
  }
  return [...new Set(input)];
}

function requireKeys(params, allowed) {
  if (Object.keys(params).some(key => !allowed.includes(key))) {
    throw new AppError('invalid_params', 'A művelet ismeretlen paramétert kapott.');
  }
}

function runAction(action, params, secrets) {
  if (!['ping', 'search', 'listing_details', 'state_get', 'state_apply', 'favorites_refresh',
    'notify_test', 'notifications_pull', 'notifications_ack'].includes(action)) {
    throw new AppError('unknown_action', 'Ismeretlen művelet.');
  }
  if (!record(params)) throw new AppError('invalid_params', 'A params mezőnek objektumnak kell lennie.');
  switch (action) {
    case 'ping':
      requireKeys(params, []);
      return { version: API_VERSION, server_time: new Date().toISOString() };
    case 'search': {
      requireKeys(params, ['queries', 'countries', 'device_groups']);
      const groups = searchValues(params.device_groups, Object.keys(DEVICE_GROUPS));
      return markSearchSeen(searchEbay(searchValues(params.countries, EU_COUNTRIES),
        searchValues(params.queries, configuredQueries(groups)), secrets));
    }
    case 'state_get':
      return stateGet(params);
    case 'state_apply':
      return stateApply(params, secrets);
    case 'favorites_refresh':
      return refreshFavorites(params, secrets);
    case 'notify_test':
      requireKeys(params, []);
      return { id: queueTestNotification() };
    case 'notifications_pull':
      return notificationsPull(params);
    case 'notifications_ack':
      return notificationsAck(params);
    case 'listing_details': {
      requireKeys(params, ['source_listing_id']);
      const id = params.source_listing_id;
      if (typeof id !== 'string' || !/^v1\|\d{1,40}\|\d{1,40}$/.test(id)) {
        throw new AppError('invalid_params', 'Érvénytelen eBay-hirdetésazonosító.');
      }
      return listingDetails(id, secrets);
    }
  }
}

function doPost(event) {
  let requestId = null;
  try {
    const post = event?.postData;
    const raw = post?.contents;
    if (post?.length > BODY_LIMIT || (typeof raw === 'string' && Utilities.newBlob(raw).getBytes().length > BODY_LIMIT)) {
      throw new AppError('body_too_large', 'A kérés törzse legfeljebb 10 KB lehet.');
    }
    let request;
    try {
      request = JSON.parse(raw);
    } catch {
      throw new AppError('invalid_json', 'A kérést JSON-ként kell elküldeni.');
    }
    const properties = PropertiesService.getScriptProperties();
    const tokens = (properties.getProperty('CLIENT_TOKENS') || '').split(',').map(value => value.trim()).filter(Boolean);
    if (!validToken(request?.token, tokens)) return jsonOutput({ ok: false, error: { code: 'unauthorized' } });

    const protectedValues = [...tokens, properties.getProperty('NTFY_TOPIC')?.trim(), properties.getProperty('EBAY_CLIENT_ID')?.trim(),
      properties.getProperty('EBAY_CLIENT_SECRET')?.trim(), CacheService.getScriptCache().get(OAUTH_CACHE_KEY)];
    if (typeof request.request_id === 'string' && /^[a-z0-9_.:-]{1,128}$/i.test(request.request_id)
      && redactText(request.request_id, protectedValues) === request.request_id) {
      requestId = request.request_id;
    }
    const params = request.params === undefined ? {} : request.params;
    const data = runAction(request.action, params, protectedValues.filter(Boolean));
    return jsonOutput({ ok: true, data, request_id: requestId });
  } catch (error) {
    return jsonOutput({
      ok: false,
      error: error instanceof AppError
        ? { code: error.code, message: error.message }
        : { code: 'internal_error', message: 'Belső hiba történt. Próbáld újra.' },
      request_id: requestId,
    });
  }
}

function doGet() {
  return ContentService.createTextOutput('Console Deal Finder API').setMimeType(ContentService.MimeType.TEXT);
}
