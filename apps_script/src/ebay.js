const EBAY_ROOT = 'https://api.ebay.com';
const OAUTH_CACHE_KEY = 'ebay:application_token';
const EBAY_DAILY_LIMIT = 5000;

class AppError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function redactText(value, secrets) {
  if (typeof value !== 'string') return value;
  const strings = [...new Set(secrets.filter(Boolean))].sort((a, b) => b.length - a.length);
  if (!strings.length) return value;
  const pattern = strings.map(secret => secret.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|');
  return value.replace(new RegExp(pattern, 'gi'), '[KITAKARVA]');
}

function redactContact(value, secrets) {
  const text = redactText(value, secrets);
  return typeof text === 'string'
    ? text.replace(/[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+/gi, '[KITAKARVA]')
      .replace(/(^|[^\w])(?:\+|00)\d(?:[ .()-]*\d){7,14}(?!\d)/g, '$1[KITAKARVA]')
    : text;
}

function sellerIdentities(seller) {
  return [seller?.username, seller?.email, seller?.name]
    .filter(value => typeof value === 'string' && value.trim());
}

function safeWarning(value, secrets) {
  if (Array.isArray(value)) return value.map(part => safeWarning(part, secrets));
  if (record(value)) {
    const forbidden = /seller|buyer|user.?name|feedback|email|phone|address/i;
    if (forbidden.test(String(value.name ?? ''))) return '[KITAKARVA]';
    return Object.fromEntries(Object.entries(value)
      .filter(([key]) => !forbidden.test(key))
      .map(([key, val]) => [redactText(key, secrets), safeWarning(val, secrets)]));
  }
  return redactContact(value, secrets);
}

function dailyCounter(kind, count = 0) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) {
    throw new AppError('counter_busy', 'A hívásszámláló foglalt. Próbáld újra.');
  }
  try {
    const day = Utilities.formatDate(new Date(), 'Europe/Budapest', 'yyyy-MM-dd');
    const key = 'CDF_CALLS_' + day;
    const properties = PropertiesService.getScriptProperties();
    const saved = properties.getProperty(key);
    const totals = saved ? JSON.parse(saved) : { daily_api_calls: 0, daily_browse_calls: 0 };
    if (count) {
      if (kind === 'browse' && totals.daily_browse_calls + count > EBAY_DAILY_LIMIT) {
        throw new AppError('daily_quota', 'Elfogyott az eBay napi Browse-híváskerete.');
      }
      totals.daily_api_calls += count;
      if (kind === 'browse') totals.daily_browse_calls += count;
      properties.setProperty(key, JSON.stringify(totals));
    }
    return totals;
  } finally {
    lock.releaseLock();
  }
}

function ebayCredentials() {
  const props = PropertiesService.getScriptProperties();
  const clientId = props.getProperty('EBAY_CLIENT_ID')?.trim();
  const secret = props.getProperty('EBAY_CLIENT_SECRET')?.trim();
  if (!clientId || !secret) {
    throw new AppError('ebay_config', 'Hiányzik az eBay App ID vagy Cert ID a Script Properties beállításból.');
  }
  return { clientId, secret };
}

function responseObject(response) {
  try {
    const value = JSON.parse(response.getContentText());
    return record(value) ? value : {};
  } catch {
    return {};
  }
}

function fetchOptions(options) {
  return { muteHttpExceptions: true, followRedirects: false, escaping: false, timeoutSeconds: 15, ...options };
}

function fetchEbay(url, options) {
  try {
    return UrlFetchApp.fetch(url, fetchOptions(options));
  } catch {
    throw new AppError('ebay_transport', 'Hálózati hiba vagy időtúllépés az eBay-hívásnál.');
  }
}

function applicationToken(credentials, countCall) {
  const cache = CacheService.getScriptCache();
  const cached = cache.get(OAUTH_CACHE_KEY);
  if (cached) return cached;
  const basic = Utilities.base64Encode(credentials.clientId + ':' + credentials.secret);
  const options = {
    method: 'post',
    headers: { Authorization: 'Basic ' + basic },
    payload: { grant_type: 'client_credentials', scope: 'https://api.ebay.com/oauth/api_scope' },
  };
  const fetchToken = () => {
    countCall('oauth', 1);
    return fetchEbay(EBAY_ROOT + '/identity/v1/oauth2/token', options);
  };
  let response = fetchToken();
  if (response.getResponseCode() === 429) {
    Utilities.sleep(1000);
    response = fetchToken();
  }
  const status = response.getResponseCode();
  if (status === 401) throw new AppError('ebay_auth', 'Az eBay elutasította az App ID vagy Cert ID értékét.');
  if (status < 200 || status >= 300) {
    throw new AppError('ebay_auth', 'Az eBay-token lekérése sikertelen (HTTP ' + status + ').');
  }
  const payload = responseObject(response);
  if (!nonempty(payload.access_token) || !Number.isSafeInteger(payload.expires_in) || payload.expires_in < 1) {
    throw new AppError('ebay_auth', 'Az eBay-token válasza hiányos vagy érvénytelen.');
  }
  cache.put(OAUTH_CACHE_KEY, payload.access_token, Math.min(payload.expires_in, 21600));
  return payload.access_token;
}

function browseHeaders(token) {
  return {
    Authorization: 'Bearer ' + token,
    'X-EBAY-C-MARKETPLACE-ID': 'EBAY_DE',
    'X-EBAY-C-ENDUSERCTX': 'contextualLocation=country%3DHU',
  };
}
