import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

const id = i => 'v1|' + (1000 + i) + '|0';
const change = (i, type, fields = {}) => ({
  op_id: 'fixture-operation-' + i, type, source: 'ebay', source_listing_id: id(i), ...fields,
});
const now = '2026-11-14T12:00:00.000Z';

function favorite(app, i, options = {}) {
  const previous = fixture('search').itemSummaries[1];
  return app.run('normalizeListing', {
    ...previous, itemId: id(i), itemWebUrl: 'https://www.ebay.de/itm/1000',
    ...options,
  }, new Date(now));
}

test('initializes named spreadsheet with headers and returns changes by revision', () => {
  const app = runtime();
  assert.equal(app.post('state_get', { since_revision: 0 }, { token: 'wrong' }).ok, false);
  assert.equal(app.sheets.size, 0);
  const initial = app.post('state_get', { since_revision: 0 }).data;
  assert.equal(app.props.get('SHEET_ID'), 'fixture-sheet');
  assert.deepEqual([...app.sheets.keys()], ['favorites', 'hidden', 'seen', 'settings', 'watches', 'alerts', 'notified', 'notifications', 'meta']);
  assert.equal(app.sheets.get('favorites').rows[0][0], 'source');
  assert.deepEqual(initial, { revision: 0, favorites: [], hidden: [], settings: [], watches: [], alerts: [], exchange_rate: null });
  const first = change(0, 'hide', { title: '=HYPERLINK("malicious")' });
  const second = change(1, 'unhide', { source_listing_id: id(0) });
  assert.equal(app.post('state_apply', { ops: [first] }).data.revision, 1);
  assert.equal(app.post('state_apply', { ops: [first] }).data.revision, 1);
  assert.equal(app.post('state_get', { since_revision: 0 }).data.hidden[0].title, first.title);
  assert.equal(app.post('state_apply', { ops: [second, first] }).data.revision, 2);
  const delta = app.post('state_get', { since_revision: 1 }).data;
  assert.equal(delta.hidden[0].deleted, true);
  assert.equal(delta.hidden[0].revision, 2);
  assert.deepEqual(app.post('state_get', { since_revision: 2 }).data.hidden, []);
});

test('favorite writes discard seller data and revisioned deletes leave tombstones', () => {
  const app = runtime();
  const listing = favorite(app, 0, { title: '+PS5 Slim Konsole' });
  const added = change(0, 'favorite_add', { listing: {
    ...listing, seller: { username: 'seller-secret', feedbackScore: 5555 }, condition: 'seller-secret',
  } });
  assert.equal(app.post('state_apply', { ops: [added] }).ok, true);
  const stored = app.post('state_get', { since_revision: 0 }).data.favorites[0];
  assert.equal(stored.title, '+PS5 Slim Konsole');
  assert.equal(stored.price, '30');
  assert.doesNotMatch(JSON.stringify(app.sheets.get('favorites').rows), /seller-secret|5555|feedbackScore/);
  assert.equal(app.post('state_apply', { ops: [change(1, 'favorite_remove', { source_listing_id: id(0) })] }).ok, true);
  assert.equal(app.post('state_get', { since_revision: 1 }).data.favorites[0].deleted, true);
});

test('state application atomically validates every operation and synchronizes filters', () => {
  const app = runtime();
  const filters = { models: ['Xbox Series S'], max_price: 42, max_total: null, buying: 'fixed',
    ending: false, boards: false, order: 'newest' };
  const good = change(0, 'setting_set', { key: 'filters', value: filters });
  const bad = change(1, 'setting_set', { key: 'token', value: 'must-not-store' });
  assert.equal(app.post('state_apply', { ops: [good, bad] }).error.code, 'invalid_params');
  assert.equal(app.post('state_get', { since_revision: 0 }).data.revision, 0);
  assert.equal(app.post('state_apply', { ops: [good] }).data.revision, 1);
  assert.deepEqual(app.post('state_get', { since_revision: 0 }).data.settings[0].value, filters);
});

test('first search seeds seen, later search flags new rows and removes thirty-day-old data', () => {
  let showNew = false;
  const app = runtime({ browse: () => response(200, {
    total: showNew ? 2 : 1,
    itemSummaries: Array.from({ length: showNew ? 2 : 1 }, (_, i) => ({
      ...fixture('search').itemSummaries[1], itemId: id(i),
    })),
  }) });
  const search = () => app.post('search', { countries: ['DE'], queries: ['ps5'] }).data;
  const first = search();
  assert.equal(first.first_sync, true);
  assert.equal(first.listings[0].is_new, false);
  showNew = true;
  app.setTime('2026-12-13T12:00:00Z');
  const second = search();
  assert.equal(second.first_sync, false);
  assert.equal(second.listings.find(row => row.source_listing_id === id(1)).is_new, true);
  app.setTime('2026-12-15T12:00:00Z');
  showNew = false;
  assert.equal(search().listings[0].is_new, true);
  assert.equal(app.sheets.get('seen').rows.length, 3);
});

test('favorite refresh checks active, ended, missing and failed items outside the spreadsheet lock', () => {
  const app = runtime({ shipping: request => {
    const itemId = decodeURIComponent(new URL(request.url).pathname.split('/').pop());
    if (itemId === id(2)) return response(404);
    if (itemId === id(3)) return response(503);
    return response(200, { itemId, buyingOptions: ['AUCTION'], currentBidPrice: { value: '39', currency: 'EUR' },
      itemEndDate: itemId === id(0) ? '2099-01-01T00:00:00Z' : '2026-01-01T00:00:00Z' });
  } });
  const ops = Array.from({ length: 4 }, (_, i) => change(i, 'favorite_add', { listing: favorite(app, i) }));
  assert.equal(app.post('state_apply', { ops }).ok, true);
  app.setTime('2026-11-14T13:00:00Z');
  const update = app.post('favorites_refresh').data;
  assert.equal(update.api_calls, 5);
  assert.equal(update.daily_browse_calls, 4);
  const rows = app.post('state_get', { since_revision: 4 }).data.favorites;
  assert.deepEqual(rows.map(row => row.status), ['ACTIVE', 'ENDED', 'ENDED', 'UNKNOWN']);
  assert.equal(rows[0].current_bid, '39');
  assert.equal(rows[3].last_checked_at, now);
  assert.equal(rows[3].last_check_error_at, '2026-11-14T13:00:00.000Z');
});

test('unsupported models and accessories skip the shipping probe', () => {
  const app = runtime({ browse: () => response(200, {
    total: 3, itemSummaries: ['PS3 Konsole', 'PS5 Box leer', 'PS5 Slim Konsole'].map((title, index) => ({
      ...fixture('search').itemSummaries[2], itemId: id(index), title,
    })),
  }) });
  const result = app.post('search', { countries: ['DE'], queries: ['ps5'] }).data;
  assert.equal(result.get_item_calls, 1);
  assert.equal(result.unknown_shipping.length, 3);
  assert.ok(result.unknown_shipping.every(item => item.ships_to_hu === 'unknown'));
});
