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

function searchWithShipping(count, details = () => response(503)) {
  const base = fixture('search').itemSummaries[2];
  const items = Array.from({ length: count }, (_, i) => ({ ...base, itemId: 'v1|' + i + '|0' }));
  return runtime({ browse: () => response(200, { total: count, itemSummaries: items }), details,
    shipping: () => assert.fail('Search must never call getItem') });
}

test('unknown shipping never triggers getItem even above the former 100-item limit', () => {
  const app = searchWithShipping(102);
  const first = app.search(['DE'], ['ps5']);
  assert.equal(first.get_item_calls, 0);
  assert.equal(first.api_calls, 4);
  assert.equal(first.shipping_check.probably_no, 102);
  assert.ok(first.unknown_shipping.every(item => item.ships_to_hu === 'probably_no'));
  assert.ok([...app.cache.keys()].every(key => !key.startsWith('ebay:ship-hu:')));
});

test('opening details caches the verified destination and price for the next search, for six hours', () => {
  const app = searchWithShipping(1, () => response(200, {
    itemId: 'v1|0|0', shipToLocations: regions(['EUROPE']),
    shippingOptions: [{ shippingCostType: 'FIXED', shippingCost: { value: '12.50', currency: 'EUR' },
      shipToLocationUsedForEstimate: { country: 'HU' } }], seller: { username: 'forbidden-seller' },
  }));
  assert.equal(app.search(['DE'], ['ps5']).unknown_shipping[0].ships_to_hu, 'probably_no');
  const details = app.post('listing_details', { source_listing_id: 'v1|0|0' }).data;
  assert.equal(details.ships_to_hu, 'yes');
  assert.equal(details.shipping_cost, '12.50');
  assert.equal(app.cache.get('ebay:ship-hu:v1|0|0').ttl, 21600);
  const second = app.search(['DE'], ['ps5']);
  assert.equal(second.get_item_calls, 0);
  assert.equal(second.listings[0].total_price, '52.50');
  assert.equal(second.listings[0].ships_to_hu, 'yes');
  assert.doesNotMatch(JSON.stringify(second) + JSON.stringify([...app.cache]) + app.log.join(' '), /forbidden-seller/);
  app.setTime('2026-11-14T18:00:01Z');
  assert.equal(app.search(['DE'], ['ps5']).unknown_shipping[0].ships_to_hu, 'probably_no');
});

test('legacy yes/no cache entries are reused; unknown and failed details remain unverified', () => {
  const app = searchWithShipping(3);
  for (const [id, ships] of [[0,'yes'],[1,'no'],[2,'unknown']]) app.cache.set('ebay:ship-hu:v1|' + id + '|0', {
    value: JSON.stringify({ ships_to_hu: ships, shipping_cost: null, shipping_currency: null }), expires: Infinity,
  });
  const result = app.search(['DE'], ['ps5']);
  assert.deepEqual(result.unknown_shipping.map(item => item.ships_to_hu), ['yes','no','probably_no']);
  assert.equal(result.get_item_calls, 0);
  assert.equal(app.post('listing_details', { source_listing_id: 'v1|2|0' }).ok, false);
  assert.equal(app.search(['DE'], ['ps5']).unknown_shipping[2].ships_to_hu, 'probably_no');
});

test('known Browse shipping requires no getItem and remains yes', () => {
  const app = runtime({ browse: () => response(200, { total: 1, itemSummaries: [fixture('search').itemSummaries[1]] }) });
  const result = app.search(['DE'], ['ps5']);
  assert.equal(result.listings[0].ships_to_hu, 'yes');
  assert.equal(result.get_item_calls, 0);
});
