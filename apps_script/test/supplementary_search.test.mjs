import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

const app = runtime();
for (const [title, word, group, expected] of [
  ['PS5 Slim defekt', 'defekt', 'consoles', true],
  ['PS5 nicht defekt', 'defekt', 'consoles', false],
  ['PS5 kein Defekt', 'defekt', 'consoles', false],
  ['PS5 ohne Defekt', 'defekt', 'consoles', false],
  ['PS5 funktioniert einwandfrei', 'defekt', 'consoles', false],
  ['PS5 voll funktionsfähig, Controller defekt', 'defekt', 'consoles', false],
  ['PS5 Konsole mit Controller defekt', 'defekt', 'consoles', false],
  ['PS5 Konsole defekt, Controller funktioniert', 'defekt', 'consoles', true],
  ['PS5 Controller defekt, Stick Modul dabei', 'defekt', 'controllers', true],
  ['PS5 console, manette HS', 'hs', 'consoles', false],
  ['Manette PS5 pas HS', 'hs', 'controllers', false],
  ['Manette PS5 HS', 'hs', 'controllers', true],
  ['PS5 non HS, en bon état', 'hs', 'controllers', false],
  ['PS5 H.S.', 'hs', 'controllers', true],
]) {
  test('supplementary title: ' + title, () => {
    assert.equal(app.run('supplementaryFaultInTitle', title, word, group), expected);
  });
}

test('supplementary search keeps main data, labels title faults, filters false positives and obeys groups', () => {
  const base = fixture('search').itemSummaries[1];
  const item = (n, title, price) => ({
    ...base, itemId: 'v1|' + n + '|0', title, price: { value: price, currency: 'EUR' }, conditionId: '3000',
  });
  const app = runtime({ browse: request => {
    const url = new URL(request.url);
    assert.equal(url.searchParams.get('category_ids'), '139971');
    const filter = url.searchParams.get('filter');
    if (filter.includes('{7000}')) {
      return response(200, { total: 1, itemSummaries: [item(1, 'PS5 Slim Konsole defekt', '100')] });
    }
    assert.match(filter, /conditionIds:\{3000\}/);
    assert.ok(['ps5 defekt', 'xbox series defekt'].includes(url.searchParams.get('q')));
    return response(200, { total: 4, itemSummaries: [
      item(1, 'PS5 Slim Konsole defekt', '90'),
      item(2, 'PS5 Slim Konsole defekt', '95'),
      item(3, 'PS5 Konsole nicht defekt', '80'),
      item(4, 'PS5 Konsole mit Controller defekt', '70'),
    ] });
  } });
  const data = app.post('search', { countries: ['DE'], device_groups: ['consoles'] }).data;
  assert.equal(data.status, 'success');
  assert.equal(data.filtered_not_faulty, 4);
  assert.equal(data.listings.length, 2);
  assert.equal(data.listings.find(row => row.source_listing_id === 'v1|1|0').price, '100');
  assert.equal(data.listings.find(row => row.source_listing_id === 'v1|1|0').fault_source, 'condition');
  assert.equal(data.listings.find(row => row.source_listing_id === 'v1|2|0').fault_source, 'title');
  assert.equal(data.countries[0].queries.filter(query => query.fault_source === 'title').length, 2);
  assert.equal(data.api_calls, 5);
});

test('French controller supplement runs without console requests and preserves title provenance in favorites', () => {
  const base = fixture('search').itemSummaries[1];
  const app = runtime({ browse: request => {
    const params = new URL(request.url).searchParams;
    assert.equal(params.get('category_ids'), '117042');
    if (params.get('filter').includes('{7000}')) return response(200, { total: 0 });
    return response(200, { total: 1, itemSummaries: [{
      ...base, itemId: 'v1|98|0', itemWebUrl: 'https://www.ebay.fr/itm/98',
      title: 'Manette PS5 HS', conditionId: '3000', itemLocation: { country: 'FR' },
    }] });
  } });
  const data = app.post('search', { countries: ['FR'], device_groups: ['controllers'] }).data;
  assert.equal(data.listings.length, 1);
  assert.equal(data.listings[0].fault_source, 'title');
  assert.equal(data.listings[0].device_group, 'controllers');
  assert.equal(data.countries[0].queries.length, 6);
  assert.equal(app.post('state_apply', { ops: [{
    type: 'favorite_add', op_id: 'title-fault-favorite-op', listing: data.listings[0],
  }] }).ok, true);
  const favorite = app.post('state_get', { since_revision: 0 }).data.favorites[0];
  assert.equal(favorite.fault_source, 'title');
});

test('supplementary shipping uses the same getItem cache and main data wins even without a shipping quote', () => {
  const base = fixture('search').itemSummaries[2];
  const app = runtime({
    browse: request => {
      const params = new URL(request.url).searchParams;
      const used = params.get('filter').includes('{3000}');
      const item = { ...base, itemId: 'v1|129|0', title: 'PS5 Slim Konsole defekt', conditionId: '3000' };
      if (used) item.shippingOptions = fixture('search').itemSummaries[1].shippingOptions;
      return response(200, { total: 1, itemSummaries: [item] });
    },
    shipping: () => response(200, { itemId: 'v1|129|0', shipToLocations: { regionIncluded: [{ regionId: 'HU' }] } }),
  });
  const data = app.post('search', { countries: ['DE'], device_groups: ['consoles'] }).data;
  assert.equal(data.get_item_calls, 1);
  assert.equal(data.unknown_shipping[0].fault_source, 'condition');
  assert.equal(app.post('search', { countries: ['DE'], device_groups: ['consoles'] }).data.get_item_calls, 0);
});
