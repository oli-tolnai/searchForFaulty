import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, runtime } from './helpers.mjs';

const app = runtime();
const base = app.run('normalizeListing', {
  ...fixture('search').itemSummaries[1], title: 'PS5 Slim Konsole Drift',
}, new Date('2026-11-14T12:00:00Z'));
const now = new Date('2026-11-14T12:00:00Z');
const rule = {
  id: 'test-alert-rules', models: ['PS5 Slim'], device_groups: ['consoles'],
  enabled: true, max_total_price: 200, include_unknown_shipping: false,
};
const match = (itemChanges = {}, ruleChanges = {}) =>
  app.run('alertMatches', { ...base, ...itemChanges }, { ...rule, ...ruleChanges }, now);

test('legacy rule gets defaults and preserves its known-shipping and price behavior', () => {
  const migrated = app.run('alertDefaults', rule);
  assert.equal(migrated.name, 'Értesítési szabály');
  assert.equal(migrated.known_shipping_only, true);
  assert.deepEqual(migrated.include_keywords, []);
  assert.equal(migrated.exclude_possibly_not_faulty, true);
  assert.equal(migrated.include_title_faults, true);
  assert.equal(match(), true);
  assert.equal(match({ shipping_cost: null, total_price: null }), false);
  assert.equal(match({ shipping_cost: null, total_price: null }, { include_unknown_shipping: true }), true);
});

test('each new alert condition can exclude a listing', () => {
  const cases = [
    [{}, { device_groups: ['controllers'] }],
    [{}, { models: ['PS5 Pro'] }],
    [{}, { buying_options: 'auction' }],
    [{}, { max_price: 1 }],
    [{}, { max_total_price: 1 }],
    [{ shipping_cost: null, total_price: null }, { known_shipping_only: true }],
    [{ possibly_not_faulty: true }, {}],
    [{ is_banned: true }, { exclude_banned: true }],
    [{ fault_source: 'title' }, { include_title_faults: false }],
    [{}, { include_keywords: ['missing', 'absent'] }],
    [{}, { exclude_keywords: ['DRIFT'] }],
    [{}, { countries: ['FR'] }],
    [{}, { enabled: false }],
    [{ currency: 'USD' }, {}],
  ];
  for (const [item, rule] of cases) assert.equal(match(item, rule), false, JSON.stringify([item, rule]));
});

test('keyword checks are case-insensitive and auction time limits preserve fixed-price listings', () => {
  assert.equal(match({}, { include_keywords: ['DRIFT', 'elsewhere'], exclude_keywords: ['banned'] }), true);
  assert.equal(match({}, { ending_hours: 6 }), true);
  const auction = { buying_options: ['AUCTION'], current_bid: '25', price: null,
    end_time: '2026-11-14T18:00:00.000Z' };
  assert.equal(match(auction, { ending_hours: 6 }), true);
  assert.equal(match({ ...auction, end_time: '2026-11-14T18:00:01.000Z' }, { ending_hours: 6 }), false);
  assert.equal(match({ ...auction, end_time: null }, { ending_hours: 6 }), false);
  assert.equal(match({ ...auction, end_time: '2026-11-14T12:00:00.000Z' }, { ending_hours: 6 }), false);
});

test('combined alert conditions persist with revisions and tombstones', () => {
  const fields = { ...rule, name: 'Olcsó hibás konzol', max_price: 60, known_shipping_only: true,
    include_keywords: ['drift'], exclude_keywords: ['banned'], countries: ['DE'], ending_hours: 12,
    buying_options: 'fixed', exclude_banned: true, exclude_possibly_not_faulty: true, include_title_faults: true };
  assert.equal(match({}, fields), true);
  const result = app.post('state_apply', { ops: [{
    ...fields, type: 'alert_add', op_id: 'alert-combined-op',
  }] });
  assert.equal(result.ok, true);
  const saved = app.post('state_get', { since_revision: 0 }).data.alerts.find(row => row.id === rule.id);
  for (const [key, value] of Object.entries(fields)) assert.deepEqual(saved[key], value);
  assert.equal(app.post('state_apply', { ops: [{
    ...fields, id: 'invalid-rule-test', op_id: 'invalid-rule-op', type: 'alert_add', ending_hours: 7,
  }] }).ok, false);
});

test('existing Sheets alert rows acquire defaults without changing their revision or price', () => {
  const app = runtime();
  app.post('state_get', { since_revision: 0 });
  app.sheets.get('alerts').rows.push(['old-rule-1234', '["DualSense"]', 70, true, true, 4, false]);
  const migrated = app.post('state_get', { since_revision: 0 }).data.alerts[0];
  assert.equal(migrated.max_total_price, 70);
  assert.equal(migrated.revision, 4);
  assert.equal(migrated.known_shipping_only, false);
  assert.equal(migrated.exclude_possibly_not_faulty, true);
  assert.equal(migrated.include_title_faults, true);
  assert.deepEqual(migrated.device_groups, ['controllers']);
  assert.equal(migrated.name, 'Értesítési szabály');
});
