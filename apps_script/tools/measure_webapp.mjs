import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';

function webappUrl(value) {
  try {
    const url = new URL(value);
    if (url.origin === 'https://script.google.com' && !url.username && !url.password
      && /^\/macros\/s\/[a-z0-9_-]+\/exec$/i.test(url.pathname) && !url.search && !url.hash) return url;
  } catch {
    // Invalid input is handled below without displaying it.
  }
  throw new Error('A CDF_WEBAPP_URL értéke egy Apps Script /exec cím legyen.');
}

function redirectUrl(value) {
  try {
    const url = new URL(value);
    if (url.origin === 'https://script.googleusercontent.com' && !url.username && !url.password) return url;
  } catch {
    // Do not surface the original Location.
  }
  throw new Error('Az átirányítás célja nem a várt Google-cím.');
}

export async function callWebapp(url, token, action, request = fetch) {
  const signal = AbortSignal.timeout(action === 'search' ? 370_000 : 30_000);
  const appUrl = webappUrl(url);
  let first;
  try {
    first = await request(appUrl, {
      method: 'POST', redirect: 'manual', signal,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, action, params: {}, request_id: 'measure-' + action }),
    });
  } catch {
    throw new Error('A webapp POST kérése kudarccal zárult vagy túllépte az időkorlátot.');
  }
  if (![302, 303].includes(first.status)) {
    throw new Error('A webapp válasza nem a várt átirányítás. Ellenőrizd a telepítést és a hozzáférést.');
  }
  const target = redirectUrl(first.headers.get('location'));
  try {
    const response = await request(target, { method: 'GET', redirect: 'manual', signal });
    if (!response.ok || !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') || '')) {
      throw new Error();
    }
    const envelope = await response.json();
    if (envelope?.ok === true && envelope.request_id === 'measure-' + action
      && envelope.data && typeof envelope.data === 'object' && !Array.isArray(envelope.data)) return envelope;
    if (envelope?.ok === false && typeof envelope.error?.code === 'string') return envelope;
  } catch {
    // Never print a transport error or response body.
  }
  throw new Error('A webapp átirányított válasza nem érvényes JSON API-válasz.');
}

async function measure(url, token, action) {
  const started = performance.now();
  const response = await callWebapp(url, token, action);
  return { response, time: Math.round(performance.now() - started) };
}

async function main(env) {
  const url = webappUrl(env.CDF_WEBAPP_URL);
  const token = env.CDF_TOKEN;
  if (!token) throw new Error('A CDF_TOKEN környezeti változó hiányzik.');
  for (let index = 0; index < 6; index++) {
    const { response, time } = await measure(url, token, 'ping');
    if (!response.ok || typeof response.data.version !== 'string'
      || typeof response.data.server_time !== 'string' || !Number.isFinite(Date.parse(response.data.server_time))) {
      throw new Error('A ping sikertelen. Ellenőrizd a kliens-tokent és a webapp verzióját.');
    }
    const label = index === 0 ? 'Első ping (hidegindítás lehetséges)' : 'Ismételt ping ' + index;
    console.log(label + ': ' + time + ' ms');
  }
  const { response, time } = await measure(url, token, 'search');
  const data = response.data;
  if (!response.ok || !['success', 'partial', 'error'].includes(data.status) || !Array.isArray(data.listings)
    || !Array.isArray(data.unknown_shipping) || !Number.isSafeInteger(data.api_calls) || data.api_calls < 0) {
    throw new Error('A keresés nem adott érvényes mérési adatot.');
  }
  const status = { success: 'sikeres', partial: 'részleges', error: 'sikertelen' }[data.status];
  console.log('Teljes keresés: ' + time + ' ms (' + status + ')');
  console.log('Találatok: ' + (data.listings.length + data.unknown_shipping.length));
  console.log('Ismeretlen szállítás: ' + data.unknown_shipping.length);
  console.log('Felhasznált eBay API-hívások: ' + data.api_calls);
  const invalidToken = randomBytes(32).toString('base64url');
  const invalid = await callWebapp(url, invalidToken, 'ping');
  const denied = invalid.ok === false && invalid.error.code === 'unauthorized'
    && Object.keys(invalid).length === 2 && Object.keys(invalid.error).length === 1;
  console.log('Hibás token elutasítva: ' + (denied ? 'igen' : 'nem'));
  if (!denied || data.status !== 'success') process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
