import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, ids, response, runtime } from './helpers.mjs';

const titles = [...fixture('model_titles'), ...fixture('diagnosed_titles')];
const classifier = runtime();
for (const [title, item_type, console_model, is_banned] of titles) {
  test('prototype classification: ' + title, () => {
    assert.deepEqual(classifier.run('classifyItem', title), { item_type, console_model, is_banned });
  });
}

const now = new Date('2026-11-14T12:00:00Z');

test('prototype listing normalization', () => {
  const [auction, fixed, unknown, expired] = fixture('search').itemSummaries;
  const normalize = item => classifier.run('normalizeListing', item, now);
  const bid = normalize(auction);
  assert.equal(bid.price, null);
  assert.equal(bid.current_bid, '35');
  assert.equal(bid.bid_count, 2);
  assert.equal(bid.total_price, '50');
  assert.equal(bid.status, 'ACTIVE');
  assert.equal(normalize(expired).status, 'ENDED');
  const offer = normalize(fixed);
  assert.equal(offer.price, '30');
  assert.equal(offer.shipping_cost, '0');
  assert.equal(offer.total_price, offer.price);
  assert.equal('seller' in offer, false);
  assert.equal(normalize(unknown).shipping_cost, null);
  assert.equal(normalize(unknown).total_price, null);
  fixed.shippingOptions[0].shippingCostType = 'CALCULATED';
  assert.equal(normalize(fixed).shipping_cost, null);
  delete auction.itemEndDate;
  assert.equal(normalize(auction).status, 'UNKNOWN');
});

test('prototype creation date takes precedence over origin date', () => {
  const item = fixture('search').itemSummaries[1];
  const listedAt = () => classifier.run('normalizeListing', item, now).listed_at;
  assert.equal(listedAt(), null);
  item.itemOriginDate = '2026-01-01T00:00:00Z';
  item.itemCreationDate = '2026-02-01T00:00:00Z';
  assert.equal(listedAt(), '2026-02-01T00:00:00.000Z');
  item.itemCreationDate = 'invalid';
  assert.equal(listedAt(), '2026-01-01T00:00:00.000Z');
});

for (const [title, expected] of [
  ['Sony PlayStation 5 PS5 Slim Digital Edition 1TB NEU 19% MwSt - Händler', true],
  ['PS5 Slim NEU Lüfter defekt', false],
  ['Xbox Series X sealed for parts', false],
  ['PS5 Slim Konsole', false],
]) {
  test('prototype possibly not faulty: ' + title, () => {
    const item = { ...fixture('search').itemSummaries[1], title };
    assert.equal(classifier.run('normalizeListing', item, now).possibly_not_faulty, expected);
  });
}

test('prototype retries 429 and paginates to five pages', () => {
  let attempts = 0;
  const app = runtime({ browse: request => {
    if (!new URL(request.url).searchParams.get('filter').includes('{7000}')) return response(200, { total: 0 });
    return ++attempts === 1 ? response(429) : response(200, { total: 1100 });
  } });
  const result = app.search(['DE'], ['ps5']);
  assert.equal(result.status, 'success');
  assert.deepEqual(result.countries[0].queries[0].warnings, ['Az ország keresése elérte az ötoldalas korlátot.']);
  assert.deepEqual(app.sleeps, [1000]);
  assert.deepEqual(app.calls.slice(1).filter(call => new URL(call.url).searchParams.get('filter').includes('{7000}'))
    .map(call => new URL(call.url).searchParams.get('offset')),
    ['0', '0', '200', '400', '600', '800']);
  assert.doesNotMatch(app.log.join(' '), /fixture-application-token/);
});

test('partial search preserves sorting, deduplication and call counts, without automatic shipping checks', () => {
  const sample = fixture('search');
  const app = runtime({ browse: request => {
    assert.equal(request.headers['X-EBAY-C-MARKETPLACE-ID'], 'EBAY_DE');
    assert.equal(request.headers['X-EBAY-C-ENDUSERCTX'], 'contextualLocation=country%3DHU');
    const params = new URL(request.url).searchParams;
    if (!params.get('filter').includes('{7000}')) return response(200, { total: 0 });
    assert.ok(['ps5', 'xbox series'].includes(params.get('q')));
    const filters = params.get('filter').split(',');
    assert.deepEqual(filters.slice(0, 3), ['conditionIds:{7000}', 'buyingOptions:{AUCTION|FIXED_PRICE}', 'deliveryCountry:HU']);
    if (filters[3] === 'itemLocationCountry:DE') return response(200, sample);
    assert.equal(filters[3], 'itemLocationCountry:FR');
    return response(503);
  } });
  const countries = ['DE', 'FR'];
  const queries = ['ps5', 'xbox series'];
  const result = app.search(countries, queries);
  assert.equal(result.status, 'partial');
  assert.equal(result.api_calls, 7);
  assert.equal(result.daily_api_calls, 7);
  assert.equal(result.daily_browse_calls, 6);
  assert.equal(result.filtered_non_eu, 4);
  assert.deepEqual(ids(result.listings), ['fixed', 'auction']);
  assert.deepEqual(ids(result.unknown_shipping), ['unknown-shipping']);
  assert.deepEqual(result.unknown_shipping_breakdown, {
    by_buying_type: { auction: 0, fixed_price: 1 }, by_country: { DE: { auction: 0, fixed_price: 1 } },
  });
  const [de, fr] = result.countries;
  assert.equal(de.status, 'success');
  assert.deepEqual(de.queries.map(query => query.query), [...queries, 'ps5 defekt', 'xbox series defekt']);
  assert.deepEqual(de.queries[0].warnings, [{ errorId: 123, message: 'Fixture warning' }]);
  assert.equal(fr.status, 'error');
  assert.ok(fr.queries.every(query => query.error.includes('503')));
  assert.doesNotMatch(JSON.stringify(result) + app.log.join(' '), /fixture-seller/);

  const repeated = app.search(countries, queries);
  assert.deepEqual(ids(repeated.listings), ['fixed', 'auction']);
  assert.deepEqual(ids(repeated.unknown_shipping), ['unknown-shipping']);
  assert.equal(repeated.api_calls, 6);
  assert.equal(repeated.daily_api_calls, 13);
  assert.equal(app.calls.filter(call => call.url.endsWith('/oauth2/token')).length, 1);
});

test('prototype API success, total failure and invalid input', () => {
  let batches = 0;
  const app = runtime({ batchFailure: () => ++batches === 2 });
  const params = { countries: ['DE'], queries: ['ps5'] };
  assert.equal(app.post('search', params).data.status, 'success');
  const failed = app.post('search', params);
  assert.equal(failed.ok, true);
  assert.equal(failed.data.status, 'error');
  assert.match(failed.data.countries[0].queries[0].error, /időtúllépés/);
  assert.equal(app.post('search', { max_price: -1 }).error.code, 'invalid_params');
});

test('prototype unknown shipping breakdown groups auctions and fixed prices by country', () => {
  const sample = fixture('search');
  const auction = sample.itemSummaries[0];
  delete auction.shippingOptions;
  auction.itemLocation.country = 'FR';
  auction.buyingOptions.push('FIXED_PRICE');
  const app = runtime({ browse: () => response(200, sample) });
  assert.deepEqual(app.search(['DE'], ['ps5', 'xbox series']).unknown_shipping_breakdown, {
    by_buying_type: { auction: 1, fixed_price: 1 },
    by_country: { DE: { auction: 0, fixed_price: 1 }, FR: { auction: 1, fixed_price: 0 } },
  });
});

test('prototype budget leaves room for every country', () => {
  const app = runtime({ browse: () => response(200, { total: 1100 }) });
  const result = app.post('search', { device_groups: ['consoles'] }).data;
  const firstPages = app.calls.slice(1).map(call => new URL(call.url).searchParams)
    .filter(params => params.get('offset') === '0');
  assert.equal(firstPages.length, 56);
  assert.equal(new Set(firstPages.map(params => params.get('filter') + params.get('q'))).size, 56);
  assert.equal(result.status, 'partial');
  assert.equal(result.api_calls, 61);
  assert.equal(app.calls.length - 1, 60);
});

test('the API returns all six item types and counts each deduplicated listing once', () => {
  const base = fixture('search').itemSummaries[1];
  const items = [
    'PS5 Slim Konsole', 'Posten 4 PS5', 'PS5 Slim EDM-040 Mainboard',
    'PS5 Box leer', 'PS3 Konsole', 'PS5 Xbox Series X',
  ].map((title, index) => ({ ...base, itemId: String(index), title }));
  const app = runtime({ browse: request => new URL(request.url).searchParams.get('q') === 'xbox series'
    ? response(503) : response(200, { total: items.length, itemSummaries: [...items, ...items] }) });
  const result = app.post('search', { countries: ['DE'], device_groups: ['consoles'] }).data;
  assert.equal(result.status, 'partial');
  assert.equal(result.countries[0].status, 'partial');
  assert.deepEqual(result.countries[0].queries.map(query => query.status), ['success', 'error', 'success', 'success']);
  assert.equal(Object.values(result.item_type_counts).filter(count => count === 1).length, 6);
  assert.equal(Object.values(result.item_type_counts).reduce((sum, count) => sum + count, 0), 6);
  assert.deepEqual(new Set(result.listings.map(item => item.item_type)),
    new Set(['console', 'console_bundle', 'needs_review', 'mainboard', 'not_console', 'unsupported_model']));
});
