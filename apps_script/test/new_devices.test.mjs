import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

const functions = { switch: 'classifySwitch', steam_deck: 'classifySteamDeck', iphone: 'classifyIphone', gpu: 'classifyGpu' };
const live = fixture('new_device_titles_live_2026-11-17').examples;
const expected = fixture('new_device_titles_expected');
assert.equal(expected.length, live.length);
const app = runtime();
for (const row of expected) {
  test('live device title ' + row.source_index + ': ' + row.title, () => {
    assert.equal(row.title, live[row.source_index].title);
    assert.equal(row.device_group, live[row.source_index].device_group);
    assert.deepEqual(app.run(functions[row.device_group], row.title), row.expected);
  });
}

for (const [group, title, type, model] of [
  ['gpu', 'NVIDIA GeForce RTX 2060 6GB defekt', 'unsupported_model', 'Nem támogatott videokártya'],
  ['gpu', 'NVIDIA GeForce RTX 2060 Super defekt', 'gpu', 'RTX 20'],
  ['iphone', 'iPhone 11 Mainboard', 'part', 'iPhone 11'],
  ['iphone', 'nur Rückseite iPhone 13 128GB', 'part', 'iPhone 13'],
  ['iphone', 'iPhone 11 und iPhone XS Konvolut', 'needs_review', 'iPhone 11'],
  ['steam_deck', 'Steam Deck OLED Ersatz Display', 'not_console', 'Steam Deck OLED'],
  ['iphone', 'Apple iPhone 3GS 8GB A1303', 'unsupported_model', 'iPhone (régebbi modell)'],
  ['iphone', 'Apple iPhone 5c A1507 Weiß', 'unsupported_model', 'iPhone (régebbi modell)'],
  ['gpu', 'Sapphire Radeon R9 290 Tri-X OC 4GB', 'unsupported_model', 'Nem támogatott videokártya'],
  ['gpu', 'SAPPHIRE R7 250X 1GB', 'unsupported_model', 'Nem támogatott videokártya'],
  ['gpu', 'Vintage Grafikkarte ATI Sapphire X1650 PRO', 'unsupported_model', 'Nem támogatott videokártya'],
]) test(title, () => {
  const item = app.run(functions[group], title);
  assert.equal(item.item_type, type);
  assert.equal(item.console_model, model);
});

test('new groups can paginate beyond the old five-call reserve and a five-page truncation is partial', () => {
  const app = runtime({ browse: request => {
    const params = new URL(request.url).searchParams;
    const offset = Number(params.get('offset'));
    return response(200, { total: params.get('filter').endsWith('itemLocationCountry:DE') ? 1200 : 401,
      itemSummaries: [{ ...fixture('search').itemSummaries[1], title: 'iPhone 13', itemId: 'v1|' + (1000 + offset) + '|0' }] });
  } });
  const result = app.post('search', { countries: ['DE','FR'], device_groups: ['iphone'] }).data;
  assert.equal(result.status, 'partial');
  assert.equal(result.browse_search_calls, 7 * (5 + 3));
  assert.ok(result.countries.find(row => row.country === 'FR').queries.every(query => query.status === 'success'));
  assert.ok(result.countries.find(row => row.country === 'DE').queries.every(query => query.error.includes('ötoldalas')));
});

for (const [text, status] of [
  ['iCloud frei', 'free_by_seller'], ['iCloud-frei', 'free_by_seller'], ['no iCloud lock', 'free_by_seller'],
  ['ohne iCloud', 'free_by_seller'], ['FMI OFF Unlocked', 'free_by_seller'], ['FMI ON Unlocked', 'locked'],
  ['Icload Sperre', 'locked'], ['MDM Sperre', 'locked'], ['locked', 'locked'], ['bloqué', 'locked'],
  ['ohne Simlock', 'unknown'], ['simlockfrei', 'unknown'], ['unlocked', 'unknown'], ['débloqué', 'unknown'],
  ['entsperrt', 'unknown'], ['iCloud frei aber FMI ON', 'locked'],
]) test('iCloud is distinct from SIM lock: ' + text, () => {
  assert.equal(app.run('iphoneCloudStatus', text), status);
});

test('each new group requests only its configured category/queries and never probes shipping', () => {
  for (const [group, category, queries, title] of [
    ['switch','139971',['nintendo switch'],'Nintendo Switch V2'],
    ['steam_deck','139971',['steam deck'],'Steam Deck LCD'],
    ['iphone','9355',[11,12,13,14,15,16,17].map(n => 'iphone ' + n),'iPhone 13'],
    ['gpu','27386',['rtx','radeon'],'RTX 3080'],
  ]) {
    const seen = [];
    const app = runtime({ browse: request => {
      const params = new URL(request.url).searchParams;
      seen.push(params.get('q'));
      assert.equal(params.get('category_ids'), category);
      assert.match(params.get('filter'), /conditionIds:\{7000\}.*buyingOptions:\{AUCTION\|FIXED_PRICE\}.*deliveryCountry:HU.*itemLocationCountry:DE/);
      return response(200, { total: 1, itemSummaries: [{ ...fixture('search').itemSummaries[2], itemId: 'v1|123|0', itemWebUrl: 'https://www.ebay.de/itm/123', title }] });
    }, shipping: () => assert.fail('No search-time getItem') });
    const data = app.post('search', { countries: ['DE'], device_groups: [group] }).data;
    assert.deepEqual(seen, queries);
    assert.equal(data.get_item_calls, 0);
    assert.equal(data.unknown_shipping.length, 1);
    assert.equal(data.unknown_shipping[0].device_group, group);
    assert.equal(data.unknown_shipping[0].ships_to_hu, 'probably_no');
    const result = app.post('state_apply', { ops: [{ type: 'favorite_add', op_id: 'new-group-favorite-' + group,
      listing: data.unknown_shipping[0] }] });
    assert.equal(result.ok, true);
    assert.equal(app.post('state_get', { since_revision: 0 }).data.favorites[0].device_group, group);
  }
});

test('description-level iCloud lock is returned without seller data', () => {
  const app = runtime({ browse: () => response(200, { total: 1, itemSummaries: [{
    ...fixture('search').itemSummaries[1], itemId: 'v1|123|0', title: 'iPhone 13',
  }] }), details: () => response(200, { itemId: 'v1|123|0', title: 'iPhone 13',
    description: '<p>FMI ON activation lock. secret-seller</p>', seller: { username: 'secret-seller' },
    shipToLocations: { regionIncluded: [{ regionId: 'HU' }] },
  }) });
  const data = app.post('listing_details', { source_listing_id: 'v1|123|0' }).data;
  assert.equal(data.icloud_status, 'locked');
  assert.equal(data.ships_to_hu, 'yes');
  assert.equal(app.post('search', { countries: ['DE'], device_groups: ['iphone'] }).data.listings[0].item_type, 'icloud_locked');
  assert.doesNotMatch(JSON.stringify(data) + JSON.stringify([...app.cache]), /secret-seller|username/);
});

test('new-group alert rules search only their group and watches accept their auctions', () => {
  for (const [group, model, title, expectedQueries] of [
    ['switch','Switch V2','Nintendo Switch V2 Konsole',1],
    ['steam_deck','Steam Deck LCD','Steam Deck LCD',1],
    ['iphone','iPhone 13','iPhone 13',7],
    ['gpu','RTX 30','RTX 3080 Grafikkarte',2],
  ]) {
    const app = runtime({ browse: request => {
      const url = new URL(request.url);
      return response(200, { total: url.searchParams.get('filter').endsWith('itemLocationCountry:DE') ? 1 : 0,
        itemSummaries: url.searchParams.get('filter').endsWith('itemLocationCountry:DE') ? [{
          ...fixture('search').itemSummaries[1], itemId: 'v1|123|0', itemWebUrl: 'https://www.ebay.de/itm/123', title,
        }] : [] });
    } });
    assert.equal(app.post('state_apply', { ops: [{ type: 'alert_add', op_id: 'alert-group-test-' + group,
      id: 'group-alert-' + group, models: [model], device_groups: [group], max_total_price: 100,
      enabled: true, include_unknown_shipping: false }] }).ok, true);
    app.run('checkNewListingAlerts');
    assert.equal(app.calls.filter(call => call.url.includes('item_summary/search')).length, expectedQueries * 27);
    assert.equal(app.sheets.get('notified').rows.length, 2);
    const listing = { ...app.run('normalizeListing', { ...fixture('search').itemSummaries[0],
      itemId: 'v1|999|0', itemWebUrl: 'https://www.ebay.de/itm/999', title }, new Date('2026-11-14'), [], group) };
    assert.equal(app.post('state_apply', { ops: [{ type: 'watch_add', op_id: 'watch-group-test-' + group,
      source: 'ebay', source_listing_id: listing.source_listing_id, listing, threshold: 100, lead_minutes: 120 }] }).ok, true);
  }
});
