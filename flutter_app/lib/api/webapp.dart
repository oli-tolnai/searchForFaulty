import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';

class AppFailure implements Exception {
  const AppFailure(this.message, {this.code});
  final String message;
  final String? code;
}

class WebappSettings {
  WebappSettings(String address, String token, {this.stateId = 'default'})
    : endpoint = _endpoint(address.trim()),
      token = token.trim() {
    if (this.token.isEmpty) {
      throw const AppFailure('Add meg a kliens-tokent.');
    }
  }

  final Uri endpoint;
  final String token;
  final String stateId;

  static Uri _endpoint(String address) {
    final uri = Uri.tryParse(address);
    if (uri == null ||
        !_trustedHost(uri, 'script.google.com') ||
        !RegExp(r'^/macros/s/[\w-]+/exec$').hasMatch(uri.path) ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AppFailure(
        'A telepített Google Apps Script /exec címét add meg.',
      );
    }
    return uri;
  }

  String safeText(String text) {
    for (final secret in [
      endpoint.toString(),
      token,
      Uri.encodeComponent(token),
    ]) {
      text = text.replaceAll(secret, '[kitakarva]');
    }
    return text.replaceAll(
      RegExp(r'https?://\S+', caseSensitive: false),
      '[kitakarva]',
    );
  }
}

bool _trustedHost(Uri uri, String host) =>
    uri.scheme == 'https' &&
    uri.host == host &&
    uri.userInfo.isEmpty &&
    uri.port == 443;

class WebappClient {
  WebappClient(
    this.settings, {
    http.Client Function()? createClient,
    this.pingTimeout = const Duration(seconds: 20),
    this.searchTimeout = const Duration(seconds: 90),
  }) : _createClient = createClient ?? http.Client.new;

  final WebappSettings settings;
  final http.Client Function() _createClient;
  final Duration pingTimeout, searchTimeout;
  final Random _random = Random.secure();

  Future<PingResult> ping() =>
      _call('ping', {}, pingTimeout, PingResult.fromJson);
  Future<SearchResult> search() =>
      _call('search', {}, searchTimeout, SearchResult.fromJson);
  Future<ListingDetails> details(String id) => _call(
    'listing_details',
    {'source_listing_id': id},
    pingTimeout,
    ListingDetails.fromJson,
  );

  Future<Json> getState(int revision) =>
      _call('state_get', {'since_revision': revision}, pingTimeout, object);

  Future<Json> applyState(List<Json> ops) =>
      _call('state_apply', {'ops': ops}, pingTimeout, object);

  Future<Json> refreshFavorites() =>
      _call('favorites_refresh', {}, searchTimeout, object);

  Future<T> _call<T>(
    String action,
    Json params,
    Duration timeout,
    T Function(Object?) decode,
  ) async {
    final client = _createClient();
    try {
      return await _request(client, action, params, decode).timeout(timeout);
    } on TimeoutException {
      throw const AppFailure('A szerver nem válaszolt időben.');
    } on FormatException {
      throw const AppFailure('A szerver érvénytelen JSON-választ adott.');
    } on AppFailure {
      rethrow;
    } on Exception {
      throw const AppFailure(
        'A webapp nem érhető el. Ellenőrizd az internetkapcsolatot.',
      );
    } finally {
      client.close();
    }
  }

  Future<T> _request<T>(
    http.Client client,
    String action,
    Json params,
    T Function(Object?) decode,
  ) async {
    final requestId = List.generate(
      16,
      (_) => _random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final post = http.Request('POST', settings.endpoint)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'token': settings.token,
        'action': action,
        'params': params,
        'request_id': requestId,
      });
    final first = await client.send(post);
    final location = first.headers['location'];
    await first.stream.drain<void>();
    if (first.statusCode != 302 && first.statusCode != 303) {
      throw const AppFailure(
        'A webapp nem érhető el. Ellenőrizd a telepítést és a hozzáférést.',
      );
    }

    final target = location == null ? null : Uri.tryParse(location);
    if (target == null ||
        !_trustedHost(target, 'script.googleusercontent.com') ||
        target.hasFragment ||
        target.pathSegments.contains(settings.token) ||
        target.queryParametersAll.values.any(
          (values) => values.contains(settings.token),
        )) {
      throw const AppFailure(
        'A webapp váratlan helyre irányított. Ellenőrizd a címet és a hozzáférést.',
      );
    }
    final get = http.Request('GET', target)..followRedirects = false;
    final response = await http.Response.fromStream(await client.send(get));
    final contentType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (response.statusCode != 200 || contentType != 'application/json') {
      throw const AppFailure(
        'A webapp nem JSON-választ adott. Ellenőrizd a telepítést és a hozzáférést.',
      );
    }
    final fields = Fields(jsonDecode(utf8.decode(response.bodyBytes)));
    if (!fields.required<bool>('ok')) {
      final code = Fields(fields.required<Json>('error'))
          .required<String>('code');
      throw switch (code) {
        'unauthorized' => const AppFailure(
          'A kliens-token hibás.',
          code: 'unauthorized',
        ),
        'listing_not_found' => const AppFailure(
          'A hirdetés már nem elérhető',
          code: 'listing_not_found',
        ),
        _ => const AppFailure('A webapp nem tudta végrehajtani a kérést.'),
      };
    }
    if (fields.required<String>('request_id') != requestId) invalidResponse();
    return decode(fields.required<Json>('data'));
  }
}
