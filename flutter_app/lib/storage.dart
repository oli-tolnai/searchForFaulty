import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'group_results.dart';

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
      stateId: fields.json['state_id'] as String? ?? 'default',
    );
  }

  Future<void> write(WebappSettings settings) => _storage.write(
    key: _key,
    value: jsonEncode({
      'url': settings.endpoint.toString(),
      'token': settings.token,
      'state_id': settings.stateId,
    }),
  );
}

class SharedStateStore {
  const SharedStateStore(this.stateId);
  final String stateId;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    if (!RegExp(r'^[a-z0-9]{1,40}$').hasMatch(stateId)) invalidResponse();
    return File(
      '${directory.path}${Platform.pathSeparator}shared-$stateId.json',
    );
  }

  Future<Json?> read() async {
    final file = await _file();
    return await file.exists()
        ? object(jsonDecode(await file.readAsString()))
        : null;
  }

  Future<void> write(Json snapshot) async {
    final file = await _file();
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(jsonEncode(snapshot), flush: true);
    await pending.rename(file.path);
  }
}

class SearchCache {
  const SearchCache([this.stateId = 'default']);
  final String stateId;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    if (!RegExp(r'^[a-z0-9]{1,40}$').hasMatch(stateId)) invalidResponse();
    final filename = stateId == 'default'
        ? 'last-search.json'
        : 'last-search-$stateId.json';
    return File('${directory.path}${Platform.pathSeparator}$filename');
  }

  Future<GroupResults> readGroups() async {
    try {
      final file = await _file();
      if (!await file.exists()) return GroupResults();
      return GroupResults.fromJson(
        object(jsonDecode(await file.readAsString())),
      )..expire(DateTime.now());
    } on Exception {
      return GroupResults();
    }
  }

  static final _writes = <String, Future<void>>{};
  Future<void> writeGroups(GroupResults results) {
    results.expire(DateTime.now());
    final encoded = jsonEncode(results.toJson());
    final next = (_writes[stateId] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
          final file = await _file();
          final pending = File('${file.path}.tmp');
          await pending.writeAsString(encoded, flush: true);
          await pending.rename(file.path);
        });
    _writes[stateId] = next;
    return next;
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
