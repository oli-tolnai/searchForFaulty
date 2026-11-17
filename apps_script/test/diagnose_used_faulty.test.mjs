import assert from 'node:assert/strict';
import { test } from 'node:test';
import { response, runtime } from './helpers.mjs';

test('fault words must be present in titles and must not be negated', () => {
  const app = runtime();
  for (const title of ['PS5 defekt', 'Sony defekter Controller', 'PS5 Kaputt für Bastler']) {
    assert.equal(app.run('isDiagnosticFaultTitle', title, ['defekt', 'kaputt', 'bastler']), true, title);
  }
  for (const title of ['PS5 funktioniert einwandfrei – kein Defekt', 'PS5 nicht defekt', 'PS5 ohne Defekt', 'PS5 Drift']) {
    assert.equal(app.run('isDiagnosticFaultTitle', title, ['defekt', 'kaputt', 'bastler']), false, title);
  }
  assert.equal(app.run('isDiagnosticFaultTitle', 'PS5 pour pièces', ['pour pièces']), true);
  assert.equal(app.run('isDiagnosticFaultTitle', 'PS5 non funzionante', ['non funzionante']), true);
  assert.equal(app.run('isDiagnosticFaultTitle', 'PS5 un guasto – non guasto', ['guasto']), false);
});

test('pilot uses only confirmed condition IDs, compares all countries and logs a fault-only recommendation', () => {
  const hit = (itemId, title, country, conditionId) => ({
    itemId, title, itemLocation: { country }, conditionId, seller: { username: 'fixture-hidden-seller' },
  });
  const app = runtime({
    details: request => {
      const url = new URL(request.url);
      assert.match(url.pathname, /EBAY_DE\/get_item_condition_policies$/);
      assert.equal(url.searchParams.get('filter'), 'categoryIds:{139971|117042}');
      return response(200, { itemConditionPolicies: ['139971', '117042'].map(categoryId => ({
        categoryId, itemConditions: ['1000', '3000', '5000', '7000'].map(conditionId => ({
          conditionId, conditionDescription: conditionId === '3000' ? 'Gebraucht' : '',
        })),
      })) });
    },
    browse: request => {
      const url = new URL(request.url);
      const filters = url.searchParams.get('filter');
      assert.equal(request.headers['X-EBAY-C-MARKETPLACE-ID'], 'EBAY_DE');
      assert.match(filters, /deliveryCountry:HU.*buyingOptions:\{AUCTION\|FIXED_PRICE\}/);
      const category = url.searchParams.get('category_ids');
      const query = url.searchParams.get('q');
      const country = filters.match(/itemLocationCountry:(\w{2})/)[1];
      assert.ok(['DE', 'FR', 'IT', 'NL'].includes(country));
      if (filters.includes('{7000}')) return response(200, { total: 0 });
      assert.match(filters, /conditionIds:\{3000\|5000\}/);
      if (category !== '139971' || country !== 'DE' || query !== 'ps5 defekt') return response(200, { total: 0 });
      return response(200, { total: 3, itemSummaries: [
        hit('one', 'PS5 Slim Konsole defekt fixture-hidden-seller', country, '3000'),
        hit('two', 'PS5 Slim Konsole ohne Defekt', country, '5000'),
        hit('three', 'PS5 Slim Konsole defekt', country, '1000'),
      ] });
    },
  });
  app.run('diagnoseUsedFaulty');
  assert.equal(app.sheets.size, 0);
  const log = app.log.join('\n');
  assert.match(log, /total=3 .*új=2 .*cím szerint hibás=1/);
  assert.match(log, /DE \| consoles \| 0 \| 2 \| 1 \| ps5 defekt \| 1 \/ 1/);
  assert.match(log, /eBay API-hívások: 70 \(OAuth: 1, Metadata: 1, Browse: 68\)/);
  assert.doesNotMatch(log, /fixture-hidden-seller/);
});
