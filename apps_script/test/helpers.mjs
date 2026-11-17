import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import vm from 'node:vm';

const dir = new URL('../src/', import.meta.url);
const source = readdirSync(dir).filter(name => name.endsWith('.js'))
  .map(name => readFileSync(new URL(name, dir), 'utf8')).join('\n');
const script = new vm.Script(source, { filename: 'apps-script-v8.js' });

export const fixture = name => JSON.parse(readFileSync(new URL('fixtures/' + name + '.json', import.meta.url)));
export const response = (status, body = {}) => ({
  getResponseCode: () => status, getContentText: () => JSON.stringify(body),
});
const missingRoute = request => {
  throw new Error('Unexpected request: ' + new URL(request.url).pathname);
};

export function runtime({
  browse = () => response(200, { total: 0 }),
  oauth = () => response(200, fixture('token')), details = missingRoute, properties = {},
  batchFailure = () => false, shipping = () => response(503), exchange = () => response(503),
} = {}) {
  let now = Date.parse('2026-11-14T12:00:00Z');
  let locked = false;
  const props = new Map(Object.entries({
    CLIENT_TOKENS: 'test-client-token', EBAY_CLIENT_ID: 'fixture-app-id',
    EBAY_CLIENT_SECRET: 'fixture-cert-id', ...properties,
  }));
  const cache = new Map();
  const calls = [];
  const exchangeCalls = [];
  const batches = [];
  const sleeps = [];
  const log = [];
  const digests = [];
  const sheets = new Map();
  function insertSheet(initial) {
    let name = initial;
    const rows = [];
    const sheet = {
      rows,
      setName(next) { sheets.delete(name); name = next; sheets.set(name, sheet); return sheet; },
      getLastRow: () => rows.length,
      getMaxRows: () => 1000,
      getMaxColumns: () => 26,
      insertRowsAfter() {},
      insertColumnsAfter() {},
      getRange(row, column, count, width) {
        assert.ok(locked);
        assert.equal(column, 1);
        return {
          getValues: () => rows.slice(row - 1, row - 1 + count),
          setValues(values) {
            assert.equal(values.length, count);
            values.forEach((cells, index) => {
              assert.equal(cells.length, width);
              assert.ok(!cells.some(value => typeof value === 'string' && value.startsWith('=')));
              rows[row - 1 + index] = cells.map(value =>
                typeof value === 'string' && value.startsWith("'") ? value.slice(1) : value);
            });
          },
          clearContent() { rows.splice(row - 1, count); },
        };
      },
    };
    sheets.set(name, sheet);
    return sheet;
  }
  const spreadsheet = {
    getId: () => 'fixture-sheet',
    getSheets: () => Array.from(sheets.values()),
    getSheetByName: name => sheets.get(name) ?? null,
    insertSheet,
  };
  const context = vm.createContext({
    Date: class extends Date {
      constructor(...args) { super(...(args.length ? args : [now])); }
      static now() { return now; }
    },
    UrlFetchApp: {
      fetch(url, options) {
        assert.equal(locked, false);
        const request = { url, ...options };
        if (url.startsWith('https://www.ecb.europa.eu/')) {
          exchangeCalls.push(request);
          return exchange(request);
        }
        calls.push(request);
        return url.endsWith('/oauth2/token') ? oauth(request) : details(request);
      },
      fetchAll(requests) {
        assert.equal(locked, false);
        batches.push(Array.from(requests));
        calls.push(...requests);
        if (batchFailure(requests)) throw new Error('fixture timeout fixture-cert-id');
        return requests.map(request => new URL(request.url).pathname.includes('/item/') ? shipping(request) : browse(request));
      },
    },
    PropertiesService: {
      getScriptProperties: () => ({
        getProperty: key => props.get(key) ?? null,
        setProperty(key, value) {
          assert.ok(locked, 'Counter writes must be locked');
          props.set(key, value);
        },
        deleteProperty(key) { assert.ok(locked); props.delete(key); },
      }),
    },
    SpreadsheetApp: {
      create(name) {
        assert.ok(locked);
        assert.equal(name, 'Console Deal Finder – adatok');
        insertSheet('Sheet1');
        return spreadsheet;
      },
      openById(id) { assert.ok(locked); assert.equal(id, 'fixture-sheet'); return spreadsheet; },
      flush() { assert.ok(locked); },
    },
    CacheService: {
      getScriptCache: () => ({
        get: key => cache.get(key)?.expires > now ? cache.get(key).value : null,
        put: (key, value, ttl) => cache.set(key, { value, ttl, expires: now + ttl * 1000 }),
        getAll: keys => Object.fromEntries(keys.filter(key => cache.get(key)?.expires > now)
          .map(key => [key, cache.get(key).value])),
        putAll(values, ttl) {
          for (const [key, value] of Object.entries(values)) {
            cache.set(key, { value, ttl, expires: now + ttl * 1000 });
          }
        },
      }),
    },
    LockService: {
      getScriptLock: () => ({
        tryLock() { assert.equal(locked, false); locked = true; return true; },
        releaseLock() { assert.ok(locked); locked = false; },
      }),
    },
    Utilities: {
      getUuid: randomUUID,
      Charset: { UTF_8: 'utf8' },
      DigestAlgorithm: { SHA_256: 'sha256' },
      computeDigest(algorithm, value, encoding) {
        digests.push(value);
        return createHash(algorithm).update(value, encoding).digest();
      },
      newBlob: raw => ({ getBytes: () => Buffer.from(raw, 'utf8') }),
      base64Encode: raw => Buffer.from(raw).toString('base64'),
      sleep: ms => sleeps.push(ms),
      formatDate(date, zone, format) {
        if (format === 'HH:mm') return new Intl.DateTimeFormat('en-GB', {
          timeZone: zone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
        }).format(date);
        assert.equal(format, 'yyyy-MM-dd');
        const parts = new Intl.DateTimeFormat('en-GB', {
          timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit',
        }).formatToParts(date);
        const fields = Object.fromEntries(parts.map(part => [part.type, part.value]));
        return [fields.year, fields.month, fields.day].join('-');
      },
    },
    ContentService: {
      MimeType: { JSON: 'application/json', TEXT: 'text/plain' },
      createTextOutput: content => ({
        content, setMimeType(type) { this.type = type; return this; },
      }),
    },
    Logger: { log: entry => log.push(entry) },
  });
  script.runInContext(context);
  function run(name, ...args) {
    context.args = args;
    const result = vm.runInContext(name + '(...args)', context);
    return result === undefined ? undefined : JSON.parse(JSON.stringify(result));
  }
  function postRaw(contents, length = Buffer.byteLength(contents)) {
    const output = context.doPost({ postData: { contents, length } });
    assert.equal(output.type, 'application/json');
    return JSON.parse(output.content);
  }
  return {
    calls, exchangeCalls, batches, sleeps, log, cache, props, digests, run, postRaw, context, sheets,
    post: (action, params, rest) => postRaw(JSON.stringify({
      action, params, token: 'test-client-token', request_id: 'request-1', ...rest,
    })),
    setTime: time => { now = Date.parse(time); },
    search: (countries, queries) => run('searchEbay', countries, queries, []),
  };
}

export const ids = items => items.map(item => item.source_listing_id);
