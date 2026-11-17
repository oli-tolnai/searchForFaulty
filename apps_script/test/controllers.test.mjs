import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

const live = fixture('controller_titles_live_2026-11-17');
const classifier = runtime();
for (const row of [...live.category_117042_sample, ...live.without_category_extra]) {
  test('live controller title: ' + row.title, () => {
    const actual = classifier.run('classifyController', row.title);
    assert.equal(actual.item_type, row.expected_type);
    assert.equal(actual.console_model, row.expected_model);
    assert.equal(actual.is_scuf, row.expected_scuf);
  });
}

for (const [title, type, model] of [
  ['Xbox Wireless Controller schwarz defekt', 'controller', 'Xbox kontroller (generáció nem ismert)'],
  ['Xbox One wireless controller 1537', 'unsupported_model', 'Xbox One'],
  ['Xbox 1697 defekt', 'unsupported_model', 'Xbox One'],
  ['Microsoft Controller model 1708', 'unsupported_model', 'Xbox One'],
  ['Xbox 360 controller', 'unsupported_model', 'Xbox 360'],
  ['Xbox 1698 Elite', 'unsupported_model', 'Xbox Elite Series 1'],
  ['Sony CUH-ZCT2E defekt', 'unsupported_model', 'PS4 / DualShock 4'],
  ['CFI-ZCT1 defekt', 'controller', 'DualSense'],
  ['Sony CFI-ZCP1 defekt', 'controller', 'DualSense Edge'],
  ['Microsoft 1797 defekt', 'controller', 'Xbox Elite Series 2'],
  ['Sony PS5 DualSense Controller Bastler Hall Effect', 'controller', 'DualSense'],
  ['Ladestation für DualSense Controller defekt', 'not_controller', 'Ellenőrzendő'],
  ['Xbox Series Controller with paddles', 'controller', 'Xbox Series kontroller'],
]) {
  test('controller classification: ' + title, () => {
    const actual = classifier.run('classifyController', title);
    assert.equal(actual.item_type, type);
    assert.equal(actual.console_model, model);
  });
}

test('controller-only search uses four keywords, deduplicates hits and checks shipping only for eligible types', () => {
  const base = fixture('search').itemSummaries[2];
  const titles = ['DualSense Stick Drift', '2x DualSense defekt', 'Kingcontroller',
    'DualSense Stick Modul', 'PDP Victrix Xbox Series Controller', 'Xbox One Controller'];
  const items = titles.map((title, i) => ({
    ...base, itemId: 'v1|' + (900 + i) + '|0', title, seller: { username: 'redacted-seller' },
  }));
  const app = runtime({
    browse: request => {
      const url = new URL(request.url);
      assert.equal(url.searchParams.get('category_ids'), '117042');
      return response(200, { total: items.length, itemSummaries: items });
    },
    shipping: request => {
      const id = decodeURIComponent(new URL(request.url).pathname.split('/').at(-1));
      return response(200, { itemId: id, shipToLocations: { regionIncluded: [{ regionId: 'DE' }] } });
    },
  });
  const input = { countries: ['DE'], device_groups: ['controllers'] };
  const result = app.post('search', input).data;
  assert.equal(result.status, 'success');
  assert.deepEqual(result.countries[0].queries.map(query => query.query),
    ['ps5 controller', 'xbox series controller', 'xbox wireless controller', 'xbox elite controller']);
  assert.equal(result.api_calls, 8);
  assert.equal(result.get_item_calls, 3);
  assert.equal(result.unknown_shipping.length, titles.length);
  assert.ok(result.unknown_shipping.every(item => item.device_group === 'controllers'));
  assert.equal(result.unknown_shipping.filter(item => item.ships_to_hu === 'no').length, 3);
  for (const type of ['controller', 'controller_bundle', 'needs_review', 'not_controller', 'third_party', 'unsupported_model']) {
    assert.equal(result.item_type_counts[type], 1);
  }
  assert.equal(app.post('search', input).data.get_item_calls, 0);
  assert.doesNotMatch(JSON.stringify(result), /redacted-seller|"seller"/);
  assert.equal(app.post('search', { ...input, queries: ['ps5'] }).error.code, 'invalid_params');
});

test('controller alert searches only the group of the enabled model and matches Scuf', () => {
  const base = fixture('search').itemSummaries[1];
  const app = runtime({ browse: request => {
    assert.equal(new URL(request.url).searchParams.get('category_ids'), '117042');
    return response(200, { total: 1, itemSummaries: [
      { ...base, itemId: 'v1|777|0', title: 'Scuf Controller PlayStation 5' },
    ] });
  } });
  const rule = { type: 'alert_add', models: ['DualSense'], enabled: true,
    include_unknown_shipping: false, max_total_price: 999, id: 'controller-rule-1', op_id: 'controller-op-1' };
  assert.equal(app.post('state_apply', { ops: [rule, { ...rule, id: 'console-rule-0001',
    op_id: 'console-op-0001', enabled: false, models: ['PS5 Slim'] }] }).ok, true);
  app.run('checkNewListingAlerts');
  assert.equal(app.calls.length, 109);
  assert.equal(app.sheets.get('notifications').rows.length, 2);
  assert.match(JSON.stringify(app.sheets.get('notifications').rows), /Scuf Controller/);
  assert.equal(app.sheets.get('seen').rows.length, 1);
});

test('controller favorites and watches accept and retain device metadata', () => {
  const app = runtime();
  const sample = fixture('search').itemSummaries[0];
  const listing = app.run('normalizeListing', { ...sample, itemId: 'v1|97|0',
    itemWebUrl: 'https://www.ebay.de/itm/97', title: 'SCUF PS5 controller defect' },
  new Date('2026-11-14T12:00:00Z'), [], 'controllers');
  const result = app.post('state_apply', { ops: [
    { type: 'favorite_add', op_id: 'controller-favorite-97', listing },
    { type: 'watch_add', op_id: 'controller-watch-97', listing, source: 'ebay',
      source_listing_id: listing.source_listing_id, threshold: 45 },
  ] });
  assert.equal(result.ok, true);
  const state = app.post('state_get', { since_revision: 0 }).data;
  assert.equal(state.favorites[0].device_group, 'controllers');
  assert.equal(state.favorites[0].is_scuf, true);
  assert.equal(state.watches[0].title, listing.title);
});
