const ECB_RATE_URL = 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml';
const ECB_RATE_STATE = 'CDF_ECB_RATE';
const ECB_RATE_ZONE = 'Europe/Budapest';

function parseEcbRate(xml) {
  // The daily feed uses one dated Cube and self-closing currency Cubes.
  const date = xml.match(/<Cube\s+time=["'](\d{4}-\d{2}-\d{2})["']\s*>/)?.[1];
  const huf = [...xml.matchAll(/<Cube\s+([^<>]+)\/>/g)].find(match => /\bcurrency=["']HUF["']/.test(match[1]));
  const eurHuf = Number(huf?.[1].match(/\brate=["'](\d+(?:\.\d+)?)["']/)?.[1]);
  const day = date ? new Date(date + 'T00:00:00Z') : null;
  if (!day || !Number.isFinite(day.getTime()) || day.toISOString().slice(0, 10) !== date ||
      !Number.isFinite(eurHuf) || eurHuf <= 0) return null;
  return { eur_huf: eurHuf, date, source: 'ECB' };
}

function ecbRateWindow(now) {
  const date = Utilities.formatDate(now, ECB_RATE_ZONE, 'yyyy-MM-dd');
  if (Utilities.formatDate(now, ECB_RATE_ZONE, 'HH:mm') >= '16:30') return date;
  return new Date(Date.parse(date + 'T00:00:00Z') - 86400000).toISOString().slice(0, 10);
}

function ecbRateResponse(state, window) {
  return state.rate ? { ...state.rate, stale: !state.ok || state.rate.date < window } : null;
}

function ecbExchangeRate() {
  const now = new Date();
  const window = ecbRateWindow(now);
  const cache = CacheService.getScriptCache();
  const cacheKey = ECB_RATE_STATE + ':' + window;
  const hit = cache.get(cacheKey);
  if (hit !== null) return JSON.parse(hit);

  const props = PropertiesService.getScriptProperties();
  const loadRate = () => JSON.parse(props.getProperty(ECB_RATE_STATE) || '{}');
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) return ecbRateResponse(loadRate(), window);
  let previous;
  try {
    previous = loadRate();
    if (previous.window >= window) return ecbRateResponse(previous, window);
    // Reserve this publication window so search and sync do not fetch concurrently.
    props.setProperty(ECB_RATE_STATE, JSON.stringify({ window, rate: previous.rate || null, ok: false }));
  } finally {
    lock.releaseLock();
  }

  let downloaded = null;
  try {
    const response = UrlFetchApp.fetch(ECB_RATE_URL, { muteHttpExceptions: true, followRedirects: false, timeoutSeconds: 10 });
    if (response.getResponseCode() === 200) downloaded = parseEcbRate(response.getContentText());
  } catch {
    // Leave the previous quote available after transport or publication errors.
  }
  if (!downloaded || (previous.rate && downloaded.date < previous.rate.date)) {
    const fallback = ecbRateResponse({ rate: previous.rate, ok: false }, window);
    cache.put(cacheKey, JSON.stringify(fallback), 21600);
    return fallback;
  }
  if (!lock.tryLock(1000)) return ecbRateResponse(loadRate(), window);
  try {
    const saved = loadRate();
    if (saved.window !== window) return ecbRateResponse(saved, window);
    const state = { window, rate: downloaded, ok: true };
    props.setProperty(ECB_RATE_STATE, JSON.stringify(state));
    const value = ecbRateResponse(state, window);
    cache.put(cacheKey, JSON.stringify(value), 21600);
    return value;
  } finally {
    lock.releaseLock();
  }
}
