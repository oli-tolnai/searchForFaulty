import assert from 'node:assert/strict';
import { test } from 'node:test';
import { response, runtime } from './helpers.mjs';

const xml = (date, rate) => '<Envelope><Cube><Cube time="' + date +
  '"><Cube rate="' + rate + '" currency="HUF"/><Cube currency="USD" rate="1.15"/>' +
  '</Cube></Cube></Envelope>';
const feed = (status, text) => ({ getResponseCode: () => status, getContentText: () => text });

test('ECB rate is queried once per Budapest publication window and shared by search and sync', () => {
  const app = runtime({ exchange: () => feed(200, xml('2026-11-14', '392.15')) });
  app.setTime('2026-11-14T16:00:00Z');
  const first = app.post('state_get', { since_revision: 0 }).data;
  assert.deepEqual(first.exchange_rate, { eur_huf: 392.15, date: '2026-11-14', source: 'ECB', stale: false });
  assert.deepEqual(app.post('search', { countries: ['DE'], queries: ['ps5'] }).data.exchange_rate, first.exchange_rate);
  app.cache.clear();
  assert.deepEqual(app.post('state_get', { since_revision: 0 }).data.exchange_rate, first.exchange_rate);
  assert.equal(app.exchangeCalls.length, 1);
  assert.equal(app.calls.length, 2);
});

test('failed or unavailable ECB feed returns the last rate marked stale, or null before the first success', () => {
  let available = false;
  const app = runtime({ exchange: () => available ? feed(200, xml('2026-11-14', '364.40')) : response(503) });
  assert.equal(app.run('ecbExchangeRate'), null);
  assert.equal(app.run('ecbExchangeRate'), null);
  assert.equal(app.exchangeCalls.length, 1);
  available = true;
  app.setTime('2026-11-14T16:00:00Z');
  assert.equal(app.run('ecbExchangeRate').stale, false);
  available = false;
  app.setTime('2026-11-15T16:00:00Z');
  assert.deepEqual(app.run('ecbExchangeRate'), { eur_huf: 364.4, date: '2026-11-14', source: 'ECB', stale: true });
  assert.equal(app.exchangeCalls.length, 3);
  assert.equal(app.run('parseEcbRate', xml('2026-02-31', '0')), null);
});

test('currency preference is independently synchronized and rejects invalid currencies', () => {
  const app = runtime();
  const op = { type: 'setting_set', key: 'currency', op_id: 'money-currency-op', value: { currency: 'HUF' } };
  assert.equal(app.post('state_apply', { ops: [{ ...op, value: { currency: 'USD' } }] }).ok, false);
  assert.equal(app.post('state_apply', { ops: [op] }).ok, true);
  assert.deepEqual(app.post('state_get', { since_revision: 0 }).data.settings[0].value, { currency: 'HUF' });
});
