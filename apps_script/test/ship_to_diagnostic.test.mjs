import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

const title = 'PS5 Slim Konsole fixture-seller ' + '🎮'.repeat(55);
const id = index => 'v1|' + (10000 + index) + '|0';
const base = fixture('search').itemSummaries[2];
const region = regionId => ({ regionId, regionName: 'fixture-seller' });
const locations = (included, excluded = []) => ({
  regionIncluded: included.map(region), regionExcluded: excluded.map(region),
});

function diagnostic(sampleSize, details, oauth) {
  const app = runtime({
    oauth, details,
    browse: request => new URL(request.url).searchParams.get('filter').endsWith(':DE')
      ? response(200, {
        total: sampleSize,
        itemSummaries: Array.from({ length: sampleSize }, (_, i) => ({
          ...base, itemId: id(i), title,
          seller: { username: 'fixture-seller' },
        })),
      }) : response(200, { total: 0 }),
  });
  app.context.diagnoseShipToLocations();
  const items = app.log.filter(line => line.startsWith('{')).map(JSON.parse);
  return { ...app, items, output: app.log.join('\n') };
}

test('batches 21 unknown shipping listings by 20 and classifies exclusions before inclusions', () => {
  const oauthScopes = [];
  const batchSizes = [];
  const app = diagnostic(21, request => {
    const url = new URL(request.url);
    assert.equal(url.pathname, '/buy/browse/v1/item/');
    assert.equal(request.headers.Authorization, 'Bearer fixture-bulk-token');
    assert.equal(request.headers['X-EBAY-C-ENDUSERCTX'], 'contextualLocation=country%3DHU');
    const ids = url.searchParams.get('item_ids').split(',');
    batchSizes.push(ids.length);
    return response(200, { items: ids.map(itemId => ({
      itemId,
      shipToLocations: itemId === id(0) ? locations(['WORLDWIDE'], ['europeAN_Union'])
        : itemId === id(1) ? locations(['EUROPE'], ['DE']) : locations(['DE']),
      shippingOptions: [{ shippingCostType: 'FIXED', shippingCost: { value: '12', currency: 'EUR' },
        shipToLocationUsedForEstimate: { country: 'HU', postalCode: 'secret-postal-code' },
        seller: { username: 'fixture-seller', feedbackScore: 123 } }],
      seller: { username: 'fixture-seller' },
    })) });
  }, request => {
    oauthScopes.push(request.payload.scope);
    return response(200, { ...fixture('token'),
      access_token: request.payload.scope.endsWith('.bulk') ? 'fixture-bulk-token' : 'fixture-application-token',
    });
  });
  assert.deepEqual(oauthScopes, ['https://api.ebay.com/oauth/api_scope', 'https://api.ebay.com/oauth/api_scope/buy.item.bulk']);
  assert.deepEqual(batchSizes, [20, 1]);
  assert.equal(app.items.length, 21);
  assert.equal(Array.from(app.items[0].title).length, 50);
  assert.equal(app.items[0].country, 'DE');
  assert.deepEqual(app.items[0].regionExcluded, ['EUROPEAN_UNION']);
  assert.deepEqual(app.items[0].shippingOptions, [{
    shippingCostType: 'FIXED', shippingCost: { value: '12', currency: 'EUR' },
    shipToLocationUsedForEstimate: { country: 'HU' },
  }]);
  assert.match(app.output, /shipToLocations a getItems válaszában: igen, 21 tételnél/);
  assert.match(app.output, /"kizárja HU-t":1,"beleérti HU-t":1,"nem eldönthető":19/);
  assert.match(app.output, /API-hívások: 58 .*keresés: 55, további OAuth: 1, getItems: 2, getItem: 0/);
  assert.doesNotMatch(app.output, /fixture-seller|fixture-bulk-token|secret-postal-code|feedbackScore/);
});

for (const status of [200, 403]) {
  test('uses at most ten getItem calls when getItems ' + (status === 200 ? 'omits the field' : 'is denied'), () => {
    const singles = [];
    const app = diagnostic(12, request => {
      const url = new URL(request.url);
      if (url.searchParams.has('item_ids')) {
        return status === 200
          ? response(200, { items: url.searchParams.get('item_ids').split(',').map(itemId => ({ itemId })) })
          : response(403, { errors: [{ errorId: 1100, message: 'fixture-cert-id' }] });
      }
      const itemId = decodeURIComponent(url.pathname.split('/').pop());
      singles.push(itemId);
      if (itemId === id(2)) return response(404);
      return response(200, { itemId, shipToLocations: locations(['HU'], itemId === id(1) ? ['HU'] : []) });
    });
    assert.deepEqual(singles, Array.from({ length: 10 }, (_, i) => id(i)));
    assert.match(app.output, /"kizárja HU-t":1,"beleérti HU-t":8,"nem eldönthető":3/);
    assert.match(app.output, /getItem, 3\. tétel: HTTP 404/);
    assert.match(app.output, /API-hívások: 67 .*getItems: 1, getItem: 10/);
    assert.match(app.output, status === 200
      ? /shipToLocations a getItems válaszában: nem\n/
      : /getItems nem érhető el vagy megszakadt: HTTP 403, eBay hibakód: 1100/);
    assert.doesNotMatch(app.output, /fixture-cert-id/);
  });
}

test('falls back to normal OAuth if eBay refuses the bulk scope', () => {
  const app = diagnostic(1, request => response(200, {
    itemId: decodeURIComponent(new URL(request.url).pathname.split('/').pop()),
    shipToLocations: locations(['EUROPEAN_UNION']),
  }), request => request.payload.scope.endsWith('.bulk')
    ? response(400, { error: 'invalid_scope', error_description: 'fixture-cert-id' })
    : response(200, fixture('token')));
  assert.equal(app.items[0].classification, 'beleérti HU-t');
  assert.match(app.output, /HTTP 400, invalid_scope/);
  assert.match(app.output, /API-hívások: 57 .*getItems: 0, getItem: 1/);
  assert.doesNotMatch(app.output, /fixture-cert-id/);
});
