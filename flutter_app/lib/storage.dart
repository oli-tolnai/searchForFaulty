import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'api/models.dart';
import 'api/webapp.dart';

class SettingsStore {
  const SettingsStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'console_deal_finder.connection';

  Future<WebappSettings?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    final fields = Fields(jsonDecode(value));
    return WebappSettings(
      fields.required<String>('url'),
      fields.required<String>('token'),
    );
  }

  Future<void> write(WebappSettings settings) => _storage.write(
    key: _key,
    value: jsonEncode({
      'url': settings.endpoint.toString(),
      'token': settings.token,
    }),
  );
}

class SearchCache {
  const SearchCache();

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}last-search.json');
  }

  Future<SearchResult?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final result = SearchResult.fromJson(
        jsonDecode(await file.readAsString()),
      );
      return result.status == 'success' ? result : null;
    } on Exception {
      return null;
    }
  }

  Future<void> write(SearchResult result) async {
    if (result.status != 'success') return;
    final file = await _file();
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(jsonEncode(result.toCacheJson()), flush: true);
    await pending.rename(file.path);
  }
}
