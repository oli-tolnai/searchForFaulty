import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

const regions = (included = [], excluded = []) => ({
  regionIncluded: included.map(regionId => ({ regionId })),
  regionExcluded: excluded.map(regionId => ({ regionId })),
});

for (const [locations, expected] of [
  [regions(['HU']), 'yes'],
  [regions(['WORLDWIDE']), 'yes'],
  [regions(['EUROPE']), 'yes'],
  [regions(['EUROPEAN_UNION']), 'yes'],
  [regions(['DE']), 'no'],
  [regions([], ['HU']), 'no'],
  [regions(['EUROPE'], ['HU']), 'no'],
  [regions(['HU'], ['EUROPEAN_UNION']), 'no'],
  [regions(['HU'], ['DE']), 'yes'],
  [regions(), 'unknown'],
  [null, 'unknown'],
]) {
  test('classifies HU shipping: ' + JSON.stringify(locations), () => {
    assert.equal(runtime().run('shipsToHungary', locations), expected);
  });
}

function itemId(request) {
  return decodeURIComponent(new URL(request.url).pathname.split('/').pop());
}

function searchWithShipping(count, shipping, properties = {}) {
  const base = fixture('search').itemSummaries[2];
  const items = Array.from({ length: count }, (_, i) => ({ ...base, itemId: 'v1|' + i + '|0' }));
  return runtime({ browse: () => response(200, { total: count, itemSummaries: items }), shipping, properties });
}

test('getItem prices and destinations are cached, but failed requests are retried next search', () => {
  const calls = [];
  const app = searchWithShipping(4, request => {
    assert.equal(request.headers['X-EBAY-C-MARKETPLACE-ID'], 'EBAY_DE');
    assert.equal(request.headers['X-EBAY-C-ENDUSERCTX'], 'contextualLocation=country%3DHU');
    const id = itemId(request);
    calls.push(id);
    if (id === 'v1|3|0') return response(503);
    if (id === 'v1|2|0') return response(200, { itemId: id });
    return response(200, {
      itemId: id, shipToLocations: regions(id === 'v1|0|0' ? ['EUROPE'] : ['DE']),
      shippingOptions: [
        { shippingCost: { value: '1', currency: 'EUR' }, shipToLocationUsedForEstimate: { country: 'DE' } },
        { shippingCost: { value: '3', currency: 'EUR' }, shippingCostType: 'CALCULATED' },
        { shippingCost: { value: '12.50', currency: 'EUR' }, shipToLocationUsedForEstimate: { country: 'HU' } },
      ],
      seller: { username: 'forbidden-seller' },
    });
  });
  const first = app.search(['DE'], ['ps5']);
  assert.equal(first.api_calls, 8);
  assert.equal(first.daily_browse_calls, 7);
  assert.equal(first.get_item_calls, 4);
  assert.deepEqual(first.shipping_check, { initial_unknown: 4, yes: 1, no: 1, unknown: 2, failed: 1 });
  assert.equal(first.listings[0].shipping_cost, '12.50');
  assert.equal(first.listings[0].shipping_currency, 'EUR');
  assert.equal(first.listings[0].total_price, '52.50');
  assert.equal(first.unknown_shipping.find(item => item.source_listing_id === 'v1|1|0').ships_to_hu, 'no');
  assert.equal(first.unknown_shipping.find(item => item.source_listing_id === 'v1|3|0').ships_to_hu, 'unknown');
  assert.equal(app.cache.get('ebay:ship-hu:v1|2|0').ttl, 21600);
  assert.doesNotMatch(JSON.stringify(first) + app.log.join(' ') + JSON.stringify([...app.cache]), /forbidden-seller/);

  calls.length = 0;
  const second = app.search(['DE'], ['ps5']);
  assert.deepEqual(calls, ['v1|3|0']);
  assert.equal(second.get_item_calls, 1);
  assert.equal(second.api_calls, 4);
  assert.equal(second.listings[0].total_price, '52.50');
});

test('shipping check uses at most 100 getItem calls, then picks up unchecked items on the next run', () => {
  const app = searchWithShipping(102, request => response(200, {
    itemId: itemId(request), shipToLocations: regions(['HU']),
  }), { FETCH_BATCH_SIZE: '8' });
  const first = app.search(['DE'], ['ps5']);
  assert.equal(first.get_item_calls, 100);
  assert.equal(first.api_calls, 104);
  assert.equal(first.shipping_check.unknown, 2);
  assert.deepEqual(app.batches.map(batch => batch.length), [3, ...Array(12).fill(8), 4]);
  assert.equal(app.search(['DE'], ['ps5']).get_item_calls, 2);
  const cached = app.search(['DE'], ['ps5']);
  assert.equal(cached.get_item_calls, 0);
  assert.equal(cached.shipping_check.yes, 102);
});

test('a known Browse shipping price needs no getItem call', () => {
  const item = fixture('search').itemSummaries[1];
  const app = runtime({ browse: () => response(200, { total: 1, itemSummaries: [item] }) });
  const result = app.search(['DE'], ['ps5']);
  assert.equal(result.listings[0].ships_to_hu, 'yes');
  assert.equal(result.get_item_calls, 0);
});
