import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

test('controller title rules distinguish supported generations, parts, bundles and ambiguous models', () => {
  const app = runtime();
  for (const [title, expected] of fixture('controller_titles')) {
    assert.equal(app.run('classifyControllerTitle', title), expected, title);
  }
});

test('controller diagnostic discovers the shared category and measures keyword and category coverage', () => {
  const id = n => 'v1|' + n + '|0';
  const item = (n, title, country = 'DE') => ({
    itemId: id(n), title, itemLocation: { country }, seller: { username: 'hidden-seller' },
  });
  const first = item(1, 'DualSense Stick Drift');
  const second = item(2, 'DualSense Edge defekt');
  const third = item(3, 'Xbox Controller 1914');
  const fourth = item(4, 'Xbox Elite Controller Series 2');
  const key = '12345';
  const suggestion = (categoryId, categoryName) => ({ category: { categoryId, categoryName } });
  const terms = ['dualsense', 'ps5 controller', 'dualsense edge', 'xbox series controller', 'xbox wireless controller', 'xbox elite controller'];
  const app = runtime({
    details: request => {
      const url = new URL(request.url);
      if (url.pathname.endsWith('get_default_category_tree_id')) {
        assert.equal(url.searchParams.get('marketplace_id'), 'EBAY_DE');
        return response(200, { categoryTreeId: '77' });
      }
      assert.match(url.pathname, /\/77\/get_category_suggestions$/);
      const shared = suggestion(key, 'Controller & Joysticks');
      return response(200, {
        categorySuggestions: url.searchParams.get('q') === 'DualSense controller'
          ? [suggestion('12346', 'Controller-Ersatzteile'), shared]
          : [shared, suggestion('12347', 'Controller für Spielautomaten')],
      });
    },
    browse: request => {
      const url = new URL(request.url);
      const query = url.searchParams.get('q');
      const category = url.searchParams.get('category_ids');
      assert.equal(request.headers['X-EBAY-C-MARKETPLACE-ID'], 'EBAY_DE');
      assert.equal(request.headers['X-EBAY-C-ENDUSERCTX'], 'contextualLocation=country%3DHU');
      assert.equal(url.searchParams.get('limit'), '200');
      assert.equal(url.searchParams.get('filter'), 'conditionIds:{7000},deliveryCountry:HU,itemLocationCountry:DE,buyingOptions:{AUCTION|FIXED_PRICE}');
      if (!category) {
        const matches = query === 'dualsense'
          ? [first, item(5, 'DualSense Ladestation hidden-seller'), item(6, 'Off-market controller', 'US')]
          : [third];
        return response(200, { total: matches.length, itemSummaries: matches, warnings: [{ message: 'hidden-seller' }] });
      }
      assert.equal(category, key);
      if (query === 'dualsense' && url.searchParams.get('offset') === '200') {
        return response(200, { total: 201, itemSummaries: [second] });
      }
      const matches = [[first], [first], [second], [third], [third], [fourth]][terms.indexOf(query)];
      return response(200, { total: query === 'dualsense' ? 201 : matches.length, itemSummaries: matches });
    },
  });
  app.run('diagnoseControllers');
  assert.equal(app.calls.length, 13);
  assert.equal(app.sheets.size, 0);
  const log = app.log.join('\n');
  assert.match(log, /Kiválasztott kategória: 12345 – Controller & Joysticks/);
  assert.match(log, /"dualsense": total=201, lefedettség=2\/4, csak ennél=0, oldalak=2/);
  assert.match(log, /"xbox elite controller": total=1, lefedettség=1\/4, csak ennél=1/);
  assert.match(log, /"dualsense" kategória nélkül:.*a teljes kategóriás mintából hiányzik: 1/);
  assert.match(log, /DualSense Edge: 1/);
  assert.match(log, /országonként 3 első oldalas hívás, DE-ben lapozással 4/);
  assert.match(log, /13 \(OAuth: 1, Taxonomy: 3, Browse: 9\)/);
  assert.doesNotMatch(log, /hidden-seller|fixture-cert-id|Off-market controller/);
});
