import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/responses.dart';

const address = 'https://script.google.com/macros/s/test-webapp/exec';
const redirect =
    'https://script.googleusercontent.com/macros/echo?user_content_key=test';
const token = 'secret-test-token';

WebappClient mock(Future<http.Response> Function(http.Request) request) =>
    WebappClient(
      WebappSettings(address, token),
      createClient: () => MockClient(request),
      pingTimeout: const Duration(milliseconds: 150),
      searchTimeout: const Duration(seconds: 1),
    );

http.Response jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('decodes a complete search result from JSON', () async {
    String? id;
    final api = mock((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], 'search');
        id = body['request_id'] as String;
        return http.Response('', 302, headers: {'location': redirect});
      }
      return jsonResponse({
        'ok': true,
        'request_id': id,
        'data': search(unknown: [listing()]),
      });
    });
    final result = await api.search();
    expect(result.status, 'success');
    expect(result.unknownShipping.single.shipping, isNull);
    expect(result.dailyBrowseCalls, 54);
  });

  for (final status in [302, 303]) {
    test('POST follows $status with a clean GET on the allowed site', () async {
      String? id;
      final methods = <String>[];
      final api = mock((request) async {
        methods.add(request.method);
        expect(request.followRedirects, isFalse);
        if (request.method == 'POST') {
          expect(request.url.toString(), address);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['token'], token);
          expect(body['action'], 'ping');
          expect(body['params'], isEmpty);
          id = body['request_id'] as String;
          return http.Response('', status, headers: {'location': redirect});
        }
        expect(request.url.toString(), redirect);
        expect(request.bodyBytes, isEmpty);
        expect(request.headers, isEmpty);
        expect(request.url.toString(), isNot(contains(token)));
        return jsonResponse({
          'ok': true,
          'data': {
            'version': '1.0.0',
            'server_time': testTime.toIso8601String(),
          },
          'request_id': id,
        });
      });
      expect((await api.ping()).version, '1.0.0');
      expect(methods, ['POST', 'GET']);
    });
  }

  for (final target in [
    'https://script.googleusercontent.com.example.test/',
    'http://script.googleusercontent.com/',
    'https://script.googleusercontent.com:8080/',
    'https://token@script.googleusercontent.com/',
    'https://script.googleusercontent.com/macros/echo?client_token=$token',
  ]) {
    test('blocks an untrusted redirect before sending GET: $target', () async {
      final api = mock((request) async {
        expect(request.method, 'POST');
        return http.Response('', 302, headers: {'location': target});
      });
      await expectLater(
        api.ping(),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.message,
            'message',
            contains('váratlan helyre'),
          ),
        ),
      );
    });
  }

  test(
    'rejects both HTML and broken JSON without reflecting the body',
    () async {
      for (final type in ['text/html', 'application/json']) {
        final api = mock(
          (request) async => request.method == 'POST'
              ? http.Response('', 302, headers: {'location': redirect})
              : http.Response(
                  '<html>$token</html>',
                  200,
                  headers: {'content-type': type},
                ),
        );
        await expectLater(
          api.ping(),
          throwsA(
            isA<AppFailure>().having(
              (failure) => failure.message,
              'message',
              allOf(contains('JSON'), isNot(contains(token))),
            ),
          ),
        );
      }
    },
  );

  test(
    'surfaces unauthorized and listing_not_found with safe localized messages',
    () async {
      for (final code in ['unauthorized', 'listing_not_found']) {
        final api = mock((request) async {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['action'], 'listing_details');
            expect(body['params'], {'source_listing_id': 'v1|123|0'});
            return http.Response('', 303, headers: {'location': redirect});
          }
          return jsonResponse({
            'ok': false,
            'error': {'code': code, 'message': '$token $address'},
          });
        });
        await expectLater(
          api.details('v1|123|0'),
          throwsA(
            isA<AppFailure>()
                .having((failure) => failure.code, 'code', code)
                .having(
                  (failure) => failure.message,
                  'message',
                  isNot(contains(token)),
                ),
          ),
        );
      }
    },
  );

  test('times out a stalled redirected request', () async {
    final blocked = Completer<http.Response>();
    final api = mock(
      (request) async => request.method == 'POST'
          ? http.Response('', 303, headers: {'location': redirect})
          : blocked.future,
    );
    await expectLater(
      api.ping(),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.message,
          'message',
          contains('időben'),
        ),
      ),
    );
    blocked.complete(http.Response('', 500));
  });

  test('validates successful envelopes including the request ID and required fields', () async {
    final api = mock(
      (request) async => request.method == 'POST'
          ? http.Response('', 303, headers: {'location': redirect})
          : jsonResponse({'ok': true, 'request_id': 'unexpected', 'data': {}}),
    );
    await expectLater(api.search(), throwsA(isA<AppFailure>()));
  });
}
