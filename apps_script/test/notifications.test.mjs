import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, response, runtime } from './helpers.mjs';

const topic = 'private-fixture-topic';
const id = i => 'v1|' + (10000 + i) + '|0';
const now = new Date('2026-11-14T12:00:00Z');
const close = '2026-11-14T13:00:00Z';
const identity = i => ({ source: 'ebay', source_listing_id: id(i) });
const op = (i, type, values) => ({ op_id: 'fixture-op-id-' + i, type, ...values });
const state = app => app.post('state_get', { since_revision: 0 }).data;
const apply = (app, ops) => assert.equal(app.post('state_apply', { ops }).ok, true);
const ntfy = app => app.calls.filter(call => new URL(call.url).hostname === 'ntfy.sh');

function listing(app, i, end = close) {
  return app.run('normalizeListing', {
    ...fixture('search').itemSummaries[0], itemId: id(i), itemEndDate: end,
    itemWebUrl: 'https://www.ebay.de/itm/' + (10000 + i),
  }, now);
}

function watch(app, i, end) {
  return op(i, 'watch_add', { ...identity(i), listing: listing(app, i, end), threshold: 100 });
}

test('watch decisions use local day, inclusive lead and strictly below the EUR threshold', () => {
  const app = runtime();
  const base = { status: 'active', end_time: close, lead_minutes: 60, last_bid: '90', threshold: 100 };
  assert.equal(app.run('watchIsDue', base, now), true);
  const cases = [
    [{ end_time: '2026-11-14T23:20:00Z' }, new Date('2026-11-14T22:40:00Z')],
    [{ lead_minutes: 59 }, now],
    [{ last_bid: '101' }, now],
    [{ last_bid: '100' }, now],
    [{ last_bid: null }, now],
    [{ status: 'notified' }, now],
    [{ notified_at: now.toISOString() }, now],
    [{ end_time: now.toISOString() }, now],
  ];
  for (const [fields, clock] of cases) assert.equal(app.run('watchIsDue', { ...base, ...fields }, clock), false);
  const nonEuro = response(200, {
    itemId: id(1), buyingOptions: ['AUCTION'], itemEndDate: close, currentBidPrice: { value: '30', currency: 'USD' },
  });
  assert.equal(app.run('watchResult', identity(1), nonEuro, now, []).last_bid, null);
});

test('empty watches skip eBay; fetched bids, 404 and expiry update state, and a watch notifies once', () => {
  const app = runtime({
    properties: { NTFY_TOPIC: topic, FETCH_BATCH_SIZE: '2' },
    details: () => response(200, { topic }),
    shipping: request => {
      const itemId = decodeURIComponent(new URL(request.url).pathname.split('/').pop());
      if (itemId === id(2)) return response(404);
      return response(200, {
        itemId, buyingOptions: ['AUCTION'], itemEndDate: '2026-11-14T13:15:00Z',
        currentBidPrice: { value: itemId === id(1) ? '75' : '100', currency: 'EUR' },
        seller: { username: 'private-seller' },
        warnings: [{ errorId: 111, message: topic + ' private-seller' }],
      });
    },
  });
  app.run('checkAuctionWatches');
  assert.equal(app.calls.length, 0);
  apply(app, [watch(app, 1), watch(app, 2), watch(app, 3, '2026-11-14T12:10:00Z'), watch(app, 4)]);
  app.setTime('2026-11-14T12:15:00Z');
  app.run('checkAuctionWatches');
  assert.deepEqual(app.batches.map(batch => batch.length), [2, 1]);
  const watches = state(app).watches;
  assert.deepEqual(watches.map(row => row.status), ['notified', 'ended', 'ended', 'active']);
  assert.equal(watches[0].last_bid, '75');
  assert.equal(watches[0].last_checked_at, '2026-11-14T12:15:00.000Z');
  assert.equal(watches[0].end_time, '2026-11-14T13:15:00.000Z');
  assert.equal(watches[0].lead_minutes, 120);
  assert.equal(ntfy(app).length, 1);
  assert.equal(ntfy(app)[0].headers['X-Priority'], 'high');
  assert.equal(ntfy(app)[0].headers.Click, watches[0].url);
  assert.match(ntfy(app)[0].payload, /Ma 14:15-kor zárul.*75 €.*100 €/);
  assert.doesNotMatch(JSON.stringify(app.log) + JSON.stringify(watches) + ntfy(app)[0].payload, /private-(?:seller|fixture-topic)/);
  apply(app, [op(11, 'watch_update', { ...identity(1), threshold: 150, lead_minutes: 30 })]);
  apply(app, [op(12, 'watch_remove', identity(1)), { ...watch(app, 1), op_id: 'fixture-op-add-again' }]);
  app.run('checkAuctionWatches');
  assert.equal(ntfy(app).length, 1);
  assert.equal(state(app).watches[0].status, 'notified');
  app.setTime('2026-11-14T13:16:00Z');
  app.run('checkAuctionWatches');
  assert.equal(state(app).watches[0].status, 'ended');
});

test('install and removal are idempotent and keep unrelated triggers', () => {
  const app = runtime();
  const trigger = (name, schedule) => ({
    getHandlerFunction: () => name, getEventType: () => 'CLOCK', schedule,
  });
  const triggers = [trigger('unrelated', '5m')];
  app.context.ScriptApp = {
    EventType: { CLOCK: 'CLOCK' },
    getProjectTriggers: () => triggers.slice(),
    deleteTrigger: value => triggers.splice(triggers.indexOf(value), 1),
    newTrigger: name => ({
      timeBased: () => ({
        everyMinutes: minutes => ({ create: () => triggers.push(trigger(name, minutes + 'm')) }),
        everyHours: hours => ({ create: () => triggers.push(trigger(name, hours + 'h')) }),
      }),
    }),
  };
  app.run('installTriggers');
  app.run('installTriggers');
  assert.deepEqual(triggers.map(value => value.schedule), ['5m', '10m', '2h']);
  app.run('removeTriggers');
  app.run('removeTriggers');
  assert.deepEqual(triggers.map(value => value.getHandlerFunction()), ['unrelated']);
});

test('scheduled search keeps seen intact, honors rules and sends one summary with up to five titles', () => {
  const app = runtime({
    properties: { NTFY_TOPIC: topic },
    details: () => response(200),
    browse: request => {
      const url = new URL(request.url);
      if (url.searchParams.get('q') !== 'ps5' || !url.searchParams.get('filter').includes('itemLocationCountry:DE')) {
        return response(200, { total: 0 });
      }
      const base = fixture('search').itemSummaries[1];
      const itemSummaries = Array.from({ length: 10 }, (_, i) => ({
        ...base, itemId: id(i), title: i === 7 ? 'PS5 DualSense Controller' : 'PS5 Slim Konsole ' + i,
        itemWebUrl: 'https://www.ebay.de/itm/' + (10000 + i),
        shippingOptions: i === 9 ? [] : base.shippingOptions,
        price: { value: i === 8 ? '1000' : '30', currency: 'EUR' },
      }));
      return response(200, { total: itemSummaries.length, itemSummaries });
    },
  });
  app.run('checkNewListingAlerts');
  assert.equal(app.calls.length, 0);
  const options = { id: 'fixture-alert-rule', models: ['PS5 Slim'], max_total_price: 100,
    include_unknown_shipping: false, enabled: true };
  apply(app, [op(1, 'alert_add', options), op(2, 'hide', { ...identity(6), title: 'Elrejtett' })]);
  const seen = JSON.stringify(app.sheets.get('seen').rows);
  app.run('checkNewListingAlerts');
  assert.equal(JSON.stringify(app.sheets.get('seen').rows), seen);
  assert.equal(ntfy(app).length, 1);
  const sent = ntfy(app)[0];
  assert.equal(sent.headers['X-Priority'], 'default');
  assert.equal(sent.headers.Click, undefined);
  assert.match(sent.payload, /^6 új találat/);
  assert.equal(sent.payload.split('\n').length, 6);
  assert.equal(app.sheets.get('notified').rows.length, 7);
  app.run('checkNewListingAlerts');
  assert.equal(ntfy(app).length, 1);
  apply(app, [op(3, 'alert_update', { ...options, include_unknown_shipping: true })]);
  app.run('checkNewListingAlerts');
  assert.equal(ntfy(app).length, 2);
  assert.equal(ntfy(app)[1].headers.Click, 'https://www.ebay.de/itm/10009');
  assert.equal(JSON.stringify(app.sheets.get('seen').rows), seen);

  app.props.set('CDF_CALLS_2026-11-14', JSON.stringify({ daily_api_calls: 4001, daily_browse_calls: 4001 }));
  const before = app.calls.length;
  app.run('checkNewListingAlerts');
  assert.equal(app.calls.length, before);
  assert.match(app.log.at(-1), /4000 fölött/);
  apply(app, [op(4, 'alert_remove', options)]);
  assert.equal(state(app).alerts[0].deleted, true);
});

test('authenticated ntfy test uses the expected headers and protects the channel even on a fetch exception', () => {
  let success = true;
  const app = runtime({
    properties: { NTFY_TOPIC: topic },
    details: request => {
      if (!success) throw new Error('Cannot reach ' + request.url);
      return response(200, { topic });
    },
  });
  assert.equal(app.post('notify_test', {}, { token: 'wrong' }).ok, false);
  assert.equal(ntfy(app).length, 0);
  assert.deepEqual(app.post('notify_test').data, { sent: true });
  assert.equal(ntfy(app)[0].method, 'post');
  assert.equal(ntfy(app)[0].url, 'https://ntfy.sh/' + topic);
  assert.deepEqual(Object.keys(ntfy(app)[0].headers).sort(), ['Tags', 'Title', 'X-Priority']);
  assert.equal(ntfy(app)[0].headers['X-Priority'], 'default');
  success = false;
  const failure = app.post('notify_test');
  assert.equal(failure.error.code, 'ntfy_failed');
  assert.ok(!JSON.stringify([failure, app.log]).includes(topic));
});

test('ntfy diagnostics expose only safe HTTP and provider error codes', () => {
  const app = runtime({
    properties: { NTFY_TOPIC: topic },
    details: () => response(429, { code: 42901, error: 'Private URL includes ' + topic }),
  });
  const result = app.post('notify_test');
  assert.equal(result.error.code, 'ntfy_failed');
  assert.match(result.error.message, /HTTP 429, ntfy 42901/);
  app.run('diagnoseNtfy');
  assert.match(app.log.at(-1), /HTTP 429, ntfy 42901/);
  assert.ok(!JSON.stringify([result, app.log]).includes(topic));
});
