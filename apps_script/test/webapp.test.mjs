import assert from 'node:assert/strict';
import { test } from 'node:test';
import { apiErrorCode, callWebapp, searchErrorLines } from '../tools/measure_webapp.mjs';
import { fixture, response, runtime } from './helpers.mjs';

const unauthorized = { ok: false, error: { code: 'unauthorized' } };

test('missing and wrong tokens are rejected before action handling', () => {
  const app = runtime();
  assert.deepEqual(app.post('search', {}, { token: undefined }), unauthorized);
  assert.deepEqual(app.post('arbitrary-action', null, { token: 'wrong' }), unauthorized);
  assert.deepEqual(app.postRaw('null'), unauthorized);
  assert.equal(app.calls.length, 0);
  const unconfigured = runtime({ properties: { CLIENT_TOKENS: ' ,  ' } });
  assert.deepEqual(unconfigured.post('search'), unauthorized);
  assert.equal(unconfigured.calls.length, 0);
});

test('correct token and each configured rotation token is accepted', () => {
  const app = runtime({ properties: { CLIENT_TOKENS: ' test-client-token, alternate-token ' } });
  assert.deepEqual(app.post('ping'), {
    ok: true, request_id: 'request-1', data: { version: '1.0.0', server_time: '2026-11-14T12:00:00.000Z' },
  });
  assert.deepEqual(app.digests, ['test-client-token', 'test-client-token', 'alternate-token']);
  assert.equal(app.post('ping', {}, { token: 'alternate-token' }).ok, true);
  assert.deepEqual(app.post('ping', {}, { token: 'alternate-TOKEN' }), unauthorized);
  assert.equal(app.post('ping', {}, { request_id: 'prefix-fixture-cert-id' }).request_id, null);
  assert.equal(app.post('ping', {}, { request_id: 'alternate-token' }).request_id, null);
  assert.equal(app.calls.length, 0);
});

test('body limit checks UTF-8 byte length, including an event with an inaccurate length', () => {
  const app = runtime();
  const base = JSON.stringify({ action: 'ping', token: 'test-client-token' });
  assert.equal(app.postRaw(base.padEnd(10240)).ok, true);
  assert.equal(app.postRaw(base.padEnd(10241)).error.code, 'body_too_large');
  const oversized = JSON.stringify({ token: 'wrong', pad: 'ő'.repeat(6000) });
  assert.equal(app.postRaw(oversized, oversized.length).error.code, 'body_too_large');
  assert.equal(app.postRaw('{ broken').error.code, 'invalid_json');
  assert.equal(app.calls.length, 0);
});

test('unknown actions and unapproved search inputs never make a request', () => {
  const app = runtime();
  assert.equal(app.post('delete', null).error.code, 'unknown_action');
  for (const params of [{ countries: ['US'] }, { queries: ['(ps5,xbox)'] }, { countries: [] },
    { queries: 'ps5' }, { unexpected: true }, null]) {
    assert.equal(app.post('search', params).error.code, 'invalid_params');
  }
  assert.equal(app.post('listing_details', { source_listing_id: '../credentials' }).error.code, 'invalid_params');
  assert.equal(app.calls.length, 0);
  assert.equal(app.context.doGet().content, 'Console Deal Finder API');
  assert.equal(app.context.doGet().type, 'text/plain');
});

test('full search uses 54 unique Browse requests in batches of four and one OAuth request', () => {
  const app = runtime();
  const result = app.post('search').data;
  assert.equal(result.status, 'success');
  assert.deepEqual(app.batches.map(batch => batch.length), [...Array(13).fill(4), 2]);
  assert.equal(result.api_calls, 55);
  assert.equal(result.daily_browse_calls, 54);
  const [oauth, ...browse] = app.calls;
  assert.equal(oauth.method, 'post');
  assert.equal(oauth.headers.Authorization, 'Basic ' + Buffer.from('fixture-app-id:fixture-cert-id').toString('base64'));
  assert.equal(oauth.payload.grant_type, 'client_credentials');
  assert.equal(oauth.payload.scope, 'https://api.ebay.com/oauth/api_scope');
  assert.equal(app.cache.get('ebay:application_token').ttl, 7200);
  assert.ok(browse.every(call => call.followRedirects === false && call.muteHttpExceptions));
  assert.equal(new Set(browse.map(call => call.url)).size, 54);
  assert.ok(browse.every(call => new URL(call.url).searchParams.get('category_ids') === '139971'));
  assert.ok(browse.every(call => new URL(call.url).searchParams.get('limit') === '200'));
});

test('configured batch size and duplicate allowlist inputs', () => {
  const app = runtime({ properties: { FETCH_BATCH_SIZE: '2' } });
  const output = app.post('search', { countries: ['DE', 'DE', 'FR', 'IT'], queries: ['ps5', 'ps5'] });
  assert.equal(output.data.countries.length, 3);
  assert.deepEqual(app.batches.map(batch => batch.length), [2, 1]);
});

test('one persistent 429 does not stop other queries and is retried only once', () => {
  const app = runtime({ browse: request => new URL(request.url).searchParams.get('q') === 'ps5'
    ? response(429, { warnings: [{ errorId: 12519 }] }) : response(200, { total: 0 }) });
  const { data } = app.post('search', { countries: ['DE'] });
  assert.equal(data.status, 'partial');
  assert.equal(data.countries[0].queries[0].status, 'error');
  assert.match(data.countries[0].queries[0].error, /HTTP 429/);
  assert.deepEqual(data.countries[0].queries[0].warnings, [{ errorId: 12519 }, { errorId: 12519 }]);
  assert.equal(data.countries[0].queries[1].status, 'success');
  assert.equal(data.api_calls, 4);
  assert.deepEqual(app.sleeps, [1000]);
});

test('transport exception in an entire batch leaves later batches running', () => {
  let batches = 0;
  const app = runtime({ batchFailure: () => ++batches === 1, properties: { FETCH_BATCH_SIZE: '1' } });
  const output = app.post('search', { countries: ['DE'] });
  assert.equal(output.data.status, 'partial');
  assert.deepEqual(output.data.countries[0].queries.map(query => query.status), ['error', 'success']);
  assert.doesNotMatch(JSON.stringify(output), /fixture-cert-id|fixture timeout/);
});

test('daily counts reset at Budapest midnight, while the OAuth token keeps its expiry', () => {
  const app = runtime();
  const params = { countries: ['DE'], queries: ['ps5'] };
  app.setTime('2026-07-14T21:59:59Z');
  assert.equal(app.post('search', params).data.daily_api_calls, 2);
  assert.equal(app.post('search', params).data.daily_api_calls, 3);
  app.setTime('2026-07-14T22:00:00Z');
  const data = app.post('search', params).data;
  assert.equal(data.daily_api_calls, 1);
  assert.equal(data.daily_browse_calls, 1);
  assert.ok(app.props.has('CDF_CALLS_2026-07-14'));
  assert.ok(app.props.has('CDF_CALLS_2026-07-15'));
  app.setTime('2026-07-14T23:59:59Z');
  assert.equal(app.post('search', params).data.api_calls, 2);
});

test('OAuth configuration errors and transient 429 handling never surface the upstream body', () => {
  const missing = runtime({ properties: { EBAY_CLIENT_SECRET: '' } });
  assert.match(missing.post('search', { countries: ['DE'] }).data.countries[0].queries[0].error, /Cert ID/);
  assert.equal(missing.calls.length, 0);
  let oauthCalls = 0;
  const app = runtime({ oauth: () => ++oauthCalls === 1
    ? response(429, { description: 'fixture-cert-id' }) : response(200, fixture('token')) });
  const output = app.post('search', { countries: ['DE'], queries: ['ps5'] });
  assert.equal(output.data.status, 'success');
  assert.equal(output.data.api_calls, 3);
  assert.deepEqual(app.sleeps, [1000]);
  assert.doesNotMatch(JSON.stringify(output) + app.log.join(' '), /fixture-cert-id/);
});

test('OAuth permission exceptions are distinguishable from transport failures in a search', () => {
  for (const [reason, code, message] of [
    ['You do not have permission to call UrlFetchApp.fetch. Required permissions: fixture-cert-id',
      'script_permission', /Google Apps Script nem kapott engedélyt/],
    ['Address unavailable: fixture-cert-id', 'ebay_transport', /Hálózati hiba/],
  ]) {
    const app = runtime({ oauth: () => { throw new Error(reason); } });
    const { data } = app.post('search', { countries: ['DE'], queries: ['ps5'] });
    const [query] = data.countries[0].queries;
    assert.equal(data.status, 'error');
    assert.equal(data.daily_api_calls, 1);
    assert.equal(data.daily_browse_calls, 0);
    assert.equal(query.error_code, code);
    assert.match(query.error, message);
    assert.doesNotMatch(JSON.stringify(data), /fixture-cert-id/);
  }
});

test('editor OAuth diagnosis makes a fresh request and logs only status and the OAuth error code', () => {
  const app = runtime({ oauth: () => response(401, {
    error: 'invalid_client', error_description: 'fixture-cert-id', access_token: 'fixture-application-token',
  }) });
  app.cache.set('ebay:application_token', { value: 'cached-secret-token', expires: Infinity });
  app.context.diagnoseEbayToken();
  assert.equal(app.calls.length, 1);
  assert.equal(app.calls[0].payload.grant_type, 'client_credentials');
  assert.deepEqual(app.log, ['HTTP 401 | error: invalid_client']);
  assert.equal(app.cache.get('ebay:application_token').value, 'cached-secret-token');
  const successful = runtime();
  successful.context.diagnoseEbayToken();
  assert.deepEqual(successful.log, ['HTTP 200']);
  assert.equal(successful.cache.size, 0);
});

test('editor OAuth diagnosis redacts credentials in an exception and an unsafe error field', () => {
  const basic = Buffer.from('fixture-app-id:fixture-cert-id').toString('base64');
  const app = runtime({ oauth: () => {
    throw new Error('You do not have permission to call UrlFetchApp.fetch. '
      + 'fixture-app-id fixture-cert-id Basic ' + basic + ' Bearer unknown-token '
      + 'test-client-token https://example.test/private');
  } });
  app.context.diagnoseEbayToken();
  assert.match(app.log.join(' '), /You do not have permission to call UrlFetchApp\.fetch/);
  assert.doesNotMatch(app.log.join(' '), /fixture|unknown-token|test-client-token|https|example\.test/);
  assert.ok(!app.log.join(' ').includes(basic));
  const unsafe = runtime({ oauth: () => response(400, { error: 'unrecognized-secret', error_description: 'private' }) });
  unsafe.context.diagnoseEbayToken();
  assert.deepEqual(unsafe.log, ['HTTP 400 | error: [KITAKARVA]']);
});

test('measurement groups failed queries and prints safe API error codes', () => {
  const token = 'client.token[secret]';
  const message = 'A kérés sikertelen';
  const countries = [
    { queries: [{ error: message }, { error: null }] },
    { queries: [{ error: message }, { error: 'Hálózati hiba' }] },
    { queries: [{ error: token + ' https://example.test/exec Bearer upstream-token' }] },
  ];
  for (const status of ['error', 'partial']) {
    assert.deepEqual(searchErrorLines({ status, countries }, [token]), [
      '2× ' + message, '1× Hálózati hiba', '1× [KITAKARVA] [KITAKARVA] [KITAKARVA]',
    ]);
  }
  assert.deepEqual(searchErrorLines({ status: 'success', countries }, [token]), []);
  assert.equal(apiErrorCode({ error: { code: 'script_permission' } }, [token]), 'script_permission');
  assert.equal(apiErrorCode({ error: { code: 'https://example.test/exec' } }, [token]), '[KITAKARVA]');
  assert.equal(apiErrorCode({ error: { code: 'secret_token' } }, ['secret_token']), '[KITAKARVA]');
});

test('daily Browse quota prevents a further network attempt', () => {
  const app = runtime();
  app.props.set('CDF_CALLS_2026-11-14', JSON.stringify({ daily_api_calls: 5001, daily_browse_calls: 5000 }));
  const { data } = app.post('search', { countries: ['DE'], queries: ['ps5'] });
  assert.equal(data.status, 'error');
  assert.match(data.countries[0].queries[0].error, /híváskerete/);
  assert.ok(data.quota_warning);
  assert.equal(app.batches.length, 0);
});

const itemId = 'v1|12345|0';

test('getItem strips HTML, redacts sensitive fields, clips text and caches only the response model', () => {
  const app = runtime({ details: request => {
    assert.equal(new URL(request.url).pathname, '/buy/browse/v1/item/v1%7C12345%7C0');
    assert.equal(request.headers['X-EBAY-C-MARKETPLACE-ID'], 'EBAY_DE');
    assert.equal(request.headers['X-EBAY-C-ENDUSERCTX'], 'contextualLocation=country%3DHU');
    return response(200, {
      itemId,
      conditionDescription: '<p>Használt &amp; hibás</p>',
      shortDescription: '<p>Az eladó fixture-seller — user&#64;example.test</p>',
      description: '<p>Egy<br>kettő &#x1f3ae;</p><script>badScript()</script>'
        + '<style>.badStyle{}</style><iframe src="test">badFrame</iframe><!--badComment-->'
        + '<div title="1&gt;2">Három</div>' + '🎮'.repeat(8100),
      warnings: [{ errorId: 11510, seller: { username: 'fixture-seller' },
        message: 'fixture-seller fixture-cert-id fixture-application-token test-client-token' }],
      seller: { username: 'fixture-seller', feedbackScore: 321 },
      unexpected: 'raw-upstream-payload',
    });
  } });
  const params = { source_listing_id: itemId };
  const first = app.post('listing_details', params).data;
  assert.deepEqual(Object.keys(first).sort(), ['condition_description', 'description_text', 'short_description']);
  assert.equal(first.condition_description, 'Használt & hibás');
  assert.equal(first.short_description, 'Az eladó [KITAKARVA] — [KITAKARVA]');
  assert.ok(first.description_text.startsWith('Egy\nkettő 🎮\nHárom'));
  assert.equal(Array.from(first.description_text).length, 8000);
  const cache = app.cache.get('ebay:details:' + itemId);
  assert.equal(cache.ttl, 3600);
  assert.deepEqual(JSON.parse(cache.value), first);
  assert.doesNotMatch(cache.value + app.log.join(' '),
    /fixture-seller|feedbackScore|raw-upstream|badScript|badStyle|badFrame|badComment|fixture-cert-id|fixture-application-token|test-client-token/);
  assert.deepEqual(app.post('listing_details', params).data, first);
  assert.equal(app.calls.length, 2);
  app.setTime('2026-11-14T13:00:00Z');
  assert.deepEqual(app.post('listing_details', params).data, first);
  assert.equal(app.calls.length, 3);
});

test('getItem HTTP 404 has a listing_not_found code without a cached error', () => {
  const app = runtime({ details: () => response(404, { message: 'fixture-cert-id' }) });
  const output = app.post('listing_details', { source_listing_id: itemId });
  assert.equal(output.ok, false);
  assert.equal(output.error.code, 'listing_not_found');
  assert.equal(output.request_id, 'request-1');
  assert.doesNotMatch(JSON.stringify(output), /fixture-cert-id/);
  assert.equal(app.cache.has('ebay:details:' + itemId), false);
});

test('reported zero stock excludes a fixed price listing and prevents cached details', () => {
  const fixed = {
    ...fixture('search').itemSummaries[1], itemId,
    estimatedAvailabilities: [{ estimatedAvailabilityStatus: 'OUT_OF_STOCK', estimatedAvailableQuantity: 0 }],
  };
  const app = runtime({
    browse: () => response(200, { total: 1, itemSummaries: [fixed] }),
    details: () => response(200, fixed),
  });
  const result = app.post('search', { countries: ['DE'], queries: ['ps5'] }).data;
  assert.deepEqual(result.listings, []);
  assert.deepEqual(result.unknown_shipping, []);
  assert.equal(app.post('listing_details', { source_listing_id: itemId }).error.code, 'listing_not_found');
  assert.equal(app.cache.has('ebay:details:' + itemId), false);
});

test('measure client follows trusted redirect by GET, with no request body or token', async () => {
  const calls = [];
  const source = 'https://script.google.com/macros/s/fixture/exec';
  const target = 'https://script.googleusercontent.com/macros/echo?user_content_key=fixture';
  const mock = async (url, options) => {
    calls.push([url.href, options]);
    if (calls.length === 1) return new Response(null, { status: 302, headers: { Location: target } });
    return Response.json({ ok: true, data: {}, request_id: 'measure-ping' });
  };
  await callWebapp(source, 'test-client-token', 'ping', mock);
  assert.deepEqual(calls.map(([url, options]) => [url, options.method, options.redirect]),
    [[source, 'POST', 'manual'], [target, 'GET', 'manual']]);
  assert.equal(JSON.parse(calls[0][1].body).token, 'test-client-token');
  assert.equal(calls[1][1].body, undefined);
  assert.equal(calls[1][1].headers, undefined);
  await assert.rejects(callWebapp(source, 'test-client-token', 'ping', async () => new Response(null, {
    status: 303, headers: { Location: target.replace('googleusercontent.com', 'googleusercontent.com.example.test') },
  })), /nem a várt Google-cím/);
  await assert.rejects(callWebapp(source, 'test-client-token', 'ping', async (_url, opts) => opts.method === 'POST'
    ? new Response(null, { status: 303, headers: { Location: target } })
    : new Response('<html>Sign in</html>', { headers: { 'Content-Type': 'text/html' } })), /nem érvényes JSON/);
});
