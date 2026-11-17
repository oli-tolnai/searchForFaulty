import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

test('new device diagnostic classifies title fixtures without changing live groups', () => {
  const app = runtime();
  for (const [group, title, category, supported, locked = false] of fixture('new_device_titles')) {
    const actual = app.run('classifyNewDeviceTitle', group, title);
    assert.equal(actual.category, category, title);
    assert.equal(actual.supported, supported, title);
    assert.equal(actual.lock_mentioned, locked, title);
  }
  assert.equal(app.post('search', { device_groups: ['unsupported-device'] }).ok, false);
  assert.equal(app.calls.length, 0);
});

test('category selection prefers devices over replacement parts and coverage deduplicates', () => {
  const app = runtime();
  const list = [{ id: '1', name: 'Handy-Ersatzteile' }, { id: '2', name: 'Handys & Smartphones' }];
  assert.equal(app.run('newDeviceCategory', 'iphone', list).id, '2');
  assert.equal(app.run('newDeviceCategory', 'iphone', list.slice(0, 1)), null);
  const jobs = fixture('new_device_coverage').map(job => ({ query: job.query, pages: 1,
    items: new Map(job.items.map(item => [item.id, { classification: { supported: item.supported } }])) }));
  assert.deepEqual(app.run('newDeviceCoverage', jobs).rows, [
    { query: 'nintendo switch', covered: 2, only: 1 }, { query: 'switch oled', covered: 2, only: 1 },
  ]);
  assert.deepEqual(app.run('newDeviceCoverage', jobs, true).rows, [
    { query: 'nintendo switch', covered: 1, only: 0 }, { query: 'switch oled', covered: 2, only: 1 },
  ]);
});

test('complete diagnostic measures three countries, samples shipping and exports only safe title data', () => {
  const names = ['Spielkonsolen', 'Spielkonsolen', 'Handys & Smartphones', 'Grafik-/Videokarten'];
  const terms = ['Nintendo Switch Konsole', 'Steam Deck', 'iPhone 13', 'Grafikkarte RTX 3080'];
  const titles = ['Nintendo Switch OLED Konsole', 'Steam Deck LCD', 'iPhone 13 iCloud locked', 'RTX 3080 Grafikkarte'];
  const app = runtime({
    details: request => {
      const url = new URL(request.url);
      if (url.pathname.endsWith('get_default_category_tree_id')) return response(200, { categoryTreeId: '77' });
      const index = terms.indexOf(url.searchParams.get('q'));
      assert.ok(index >= 0);
      return response(200, { categorySuggestions: [{ category: { categoryId: String(10 + index), categoryName: names[index] } }] });
    },
    browse: request => {
      const params = new URL(request.url).searchParams;
      assert.equal(request.headers['X-EBAY-C-MARKETPLACE-ID'], 'EBAY_DE');
      assert.equal(request.headers['X-EBAY-C-ENDUSERCTX'], 'contextualLocation=country%3DHU');
      assert.match(params.get('filter'), /conditionIds:\{7000\},deliveryCountry:HU,buyingOptions:\{AUCTION\|FIXED_PRICE\},itemLocationCountry:(DE|FR|IT)$/);
      const country = params.get('filter').slice(-2);
      const index = Number(params.get('category_ids')) - 10;
      const item = n => ({ itemId: 'v1|' + index + country + n + '|0', title: titles[index] + ' private-seller',
        conditionId: '7000', itemLocation: { country }, seller: { username: 'private-seller' },
        ...(n === 0 ? { shippingOptions: [{ shippingCostType: 'FIXED', shippingCost: { value: '4', currency: 'EUR' } }] } : {}) });
      return response(200, { total: 2, itemSummaries: [item(0), item(1)], warnings: [{ message: 'private-seller fixture-cert-id' }] });
    },
    shipping: request => {
      const id = decodeURIComponent(new URL(request.url).pathname.split('/').at(-1));
      return response(200, { itemId: id, seller: { username: 'private-seller' }, shipToLocations: {
        regionIncluded: [{ regionId: id.includes('DE') ? 'DE' : 'WORLDWIDE' }],
        ...(id.includes('IT') ? { regionExcluded: [{ regionId: 'HU' }] } : {}),
      } });
    },
  });
  app.run('diagnoseNewDeviceGroups');
  const logs = app.log.join('\n');
  assert.match(logs, /eleve ismert HU-díj=3.*getItem-minta=3, HU igen\/nem\/nem eldönthető=1\/2\/0/);
  assert.match(logs, /eBay API-hívások: 69 \(OAuth: 1, Taxonomy: 5, Browse keresés: 51, getItem: 12\)/);
  assert.match(logs, /iCloud-\/aktiválási zárat említ: 6/);
  assert.doesNotMatch(logs, /private-seller|fixture-cert-id|fixture-app-id|test-client-token/);
  const exported = JSON.parse(app.log.find(line => line.startsWith('{"date"')));
  assert.ok(exported.examples.length);
  assert.ok(exported.examples.every(row => Object.keys(row).sort().join() === 'country,device_group,diagnostic,title'));
  assert.equal(app.sheets.size, 0);
  assert.ok([...app.cache.keys()].every(key => key === 'ebay:application_token'));
});

test('shipping sample never exceeds ten, preserves missing data, and handles failures', () => {
  const app = runtime({ shipping: request => {
    const id = decodeURIComponent(new URL(request.url).pathname.split('/').at(-1));
    if (id === '0') return response(503);
    if (id === '1') return response(200, { itemId: 'wrong-id', shipToLocations: { regionIncluded: [{ regionId: 'HU' }] } });
    return response(200, { itemId: id });
  } });
  const items = new Map(Array.from({ length: 20 }, (_, i) => [String(i), {
    known_shipping: false, classification: { supported: true },
  }]));
  const result = app.run('newDeviceShipping', items, 'fixture-token', [], () => {}, Date.now() + 60000);
  assert.equal(result.sampled, 10);
  assert.equal(result.unknown, 10);
  assert.equal(result.failed, 2);
  assert.equal(app.calls.length, 10);
  const network = runtime({ batchFailure: () => true });
  const failed = network.run('newDeviceShipping', items, 'fixture-token', [], () => {}, Number.MAX_SAFE_INTEGER);
  assert.equal(failed.unknown, 10);
  assert.equal(failed.failed, 10);
});

test('pagination, retry, rejected conditions, API errors and deadline remain explicit', () => {
  let retried = false;
  const app = runtime({ browse: request => {
    const params = new URL(request.url).searchParams;
    if (params.get('q') === 'bad') return response(400, { errors: [{ message: 'not logged' }] });
    if (!retried) { retried = true; return response(429); }
    const item = (id, country, conditionId) => ({ itemId: id, title: 'Steam Deck OLED', itemLocation: { country }, conditionId });
    return response(200, { total: 201, itemSummaries: params.get('offset') === '0'
      ? [item('a', 'DE', '7000'), item('non-eu', 'US', '7000'), item('new', 'DE', '1000')]
      : [item('b', 'DE', '7000')] });
  } });
  const jobs = ['steam deck', 'bad'].map(query => ({ group: 'steam_deck', category: { id: '123', name: 'Consoles' },
    country: 'DE', query, pages: 0, total: null, items: new Map(), rejected: 0 }));
  let calls = 0;
  app.run('measureNewDeviceJobs', jobs, 'secret-token', [], (_, n) => { calls += n; }, Number.MAX_SAFE_INTEGER);
  assert.equal(calls, 4);
  assert.equal(jobs[0].pages, 2);
  assert.equal(jobs[0].calls, 3);
  assert.equal(jobs[0].items.size, 2);
  assert.equal(jobs[0].rejected, 2);
  assert.equal(jobs[1].error, 'HTTP 400');
  const expired = { ...jobs[0], error: null, pages: 0, items: new Map() };
  app.run('measureNewDeviceJobs', [expired], 'secret-token', [], () => assert.fail('deadline must prevent HTTP'), 0);
  assert.match(expired.error, /idő- vagy híváskorlát/);
});

test('missing category stops that group rather than silently using a hardcoded id', () => {
  const app = runtime({ details: request => new URL(request.url).pathname.endsWith('get_default_category_tree_id')
    ? response(200, { categoryTreeId: '77' }) : response(403) });
  app.run('diagnoseNewDeviceGroups');
  assert.equal(app.calls.length, 6);
  assert.equal(app.batches.length, 0);
  assert.match(app.log.join('\n'), /KIMARADT: nincs kategória/);
  assert.doesNotMatch(app.log.join('\n'), /fixture-cert-id|test-client-token/);
});
