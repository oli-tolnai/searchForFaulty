import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api/models.dart';
import 'listings.dart';

String listingKey(Listing item) => '${item.source}:${item.id}';
String stateKey(Json row) => '${row['source']}:${row['source_listing_id']}';

class SavedFavorite {
  SavedFavorite(Json row)
    : savedAt = Fields(row).date('saved_at'),
      lastError = Fields(row).nullable<String>('last_check_error'),
      item = _listing(row);

  final Listing item;
  final DateTime savedAt;
  final String? lastError;

  static Listing _listing(Json row) {
    final fields = Fields(row);
    final auction = fields
        .required<List<Object?>>('buying_options')
        .contains('AUCTION');
    final price = fields.amount(auction ? 'current_bid' : 'price');
    final shipping = fields.amount('shipping_cost');
    final total =
        price != null &&
            shipping != null &&
            row['currency'] != null &&
            row['currency'] == row['shipping_currency']
        ? (double.parse(price) + double.parse(shipping)).toStringAsFixed(2)
        : null;
    return Listing.fromJson({
      ...row,
      'total_price': total,
      'condition': null,
      'fault_source': 'condition',
      'is_new': false,
    });
  }
}

class SharedState extends ChangeNotifier {
  SharedState({
    required this.readRemote,
    required this.writeRemote,
    required this.refreshRemote,
    required this.save,
    Json? restored,
    this.clock = DateTime.now,
  }) {
    if (restored != null) {
      _merge(restored);
      _queue.addAll(Fields(restored).list('pending', object));
      final syncedAt = restored['synced_at'];
      if (syncedAt is String) lastSync = DateTime.tryParse(syncedAt);
      final refreshAt = restored['favorite_refresh_at'];
      if (refreshAt is String) _lastRefresh = DateTime.tryParse(refreshAt);
      final dismissed = restored['dismissed_new'];
      if (dismissed is List) {
        _dismissedNew.addAll(dismissed.whereType<String>());
      }
    }
  }

  final Future<Json> Function(int) readRemote;
  final Future<Json> Function(List<Json>) writeRemote;
  final Future<Json> Function() refreshRemote;
  final Future<void> Function(Json) save;
  final DateTime Function() clock;
  static final _random = Random.secure();
  final _tables = {
    for (final table in ['favorites', 'hidden', 'settings'])
      table: <String, Json>{},
  };
  final _queue = <Json>[];
  final _dismissedNew = <String>{};
  Future<void>? _syncing;
  Future<void>? _refreshing;
  Future<void> _writing = Future.value();
  int _revision = 0;
  DateTime? lastSync, _lastRefresh;
  bool syncFailed = false;
  bool localSaveFailed = false;
  bool _disposed = false;
  int refreshCalls = 0;

  bool get pending => _queue.isNotEmpty;

  Iterable<SavedFavorite> get favorites =>
      _view('favorites').values
          .where((row) => row['deleted'] == false)
          .map(SavedFavorite.new);
  Iterable<Json> get hidden =>
      _view('hidden').values.where((row) => row['deleted'] == false);
  Json? get filters => _view('settings')['filters']?['value'] as Json?;
  bool isFavorite(Listing item) =>
      _view('favorites')[listingKey(item)]?['deleted'] == false;
  bool isHidden(Listing item) =>
      _view('hidden')[listingKey(item)]?['deleted'] == false;
  bool isNew(Listing item) =>
      item.isNew && !_dismissedNew.contains(listingKey(item));

  Future<void> toggleFavorite(Listing item) => _add(
    isFavorite(item)
        ? {
            'type': 'favorite_remove',
            'source': item.source,
            'source_listing_id': item.id,
          }
        : {'type': 'favorite_add', 'listing': item.toJson()},
  );

  Future<void> hide(Listing item) => _add({
    'type': 'hide',
    'source': item.source,
    'source_listing_id': item.id,
    'title': item.title,
  });
  Future<void> unhide(Json row) => _add({
    'type': 'unhide',
    'source': row['source'],
    'source_listing_id': row['source_listing_id'],
  });
  Future<void> setFilters(Json value) =>
      _add({'type': 'setting_set', 'key': 'filters', 'value': value});

  void dismissNew(Listing item) {
    if (_dismissedNew.add(listingKey(item))) changedLocally();
  }

  void searchedAgain(Iterable<Listing> previous) {
    final keys = previous.where((item) => item.isNew).map(listingKey);
    if (keys.isEmpty) return;
    _dismissedNew.addAll(keys);
    changedLocally();
  }

  void changedLocally() {
    _notify();
    unawaited(_persist().catchError((Object _) {}));
  }

  Future<void> _add(Json op) async {
    _queue.add({
      ...op,
      'op_id': List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      'local_at': clock().toUtc().toIso8601String(),
    });
    _notify();
    try {
      await _persist();
      await sync();
    } on Exception {
      // The pending operation remains available for retry in memory.
    }
  }

  Map<String, Json> _view(String table) {
    final rows = Map<String, Json>.of(_tables[table]!);
    for (final op in _queue) {
      switch ((table, op['type'])) {
        case ('favorites', 'favorite_add'):
          final listing = object(op['listing']);
          rows[stateKey(listing)] = {
            ...listing,
            'deleted': false,
            'saved_at': op['local_at'],
            'last_check_error': null,
          };
        case ('favorites', 'favorite_remove'):
        case ('hidden', 'unhide'):
          rows.remove(stateKey(op));
        case ('hidden', 'hide'):
          rows[stateKey(op)] = {
            ...op,
            'deleted': false,
            'hidden_at': op['local_at'],
          };
        case ('settings', 'setting_set'):
          rows['filters'] = {'key': 'filters', 'value': op['value']};
      }
    }
    return rows;
  }

  Future<void> sync() =>
      _syncing ??= _performSync().whenComplete(() => _syncing = null);

  Future<void> _performSync() async {
    try {
      await _persist();
      do {
        final batch = _queue.take(5).toList();
        if (batch.isNotEmpty) {
          final response = Fields(await writeRemote(batch));
          final ids = response.list(
            'applied_op_ids',
            (id) => id is String ? id : invalidResponse(),
          );
          if (batch.any((op) => !ids.contains(op['op_id']))) invalidResponse();
        }
        // Only drop acknowledged operations once the corresponding delta is available.
        _merge(await readRemote(_revision));
        final sent = batch.map((op) => op['op_id']).toSet();
        _queue.removeWhere((op) => sent.contains(op['op_id']));
        lastSync = clock();
        syncFailed = false;
        await _persist();
        _notify();
      } while (_queue.isNotEmpty);
    } on Exception {
      syncFailed = true;
      _notify();
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final now = clock();
    if (_lastRefresh != null &&
        now.difference(_lastRefresh!) < const Duration(minutes: 15)) {
      return;
    }
    try {
      await sync();
      if (syncFailed ||
          favorites.every((favorite) => favorite.item.status == 'ENDED')) {
        return;
      }
      _lastRefresh = clock();
      await _persist();
      final response = Fields(await refreshRemote());
      refreshCalls = response.count('api_calls');
      await sync();
    } on Exception {
      syncFailed = true;
      _notify();
    }
  }

  void _merge(Json payload) {
    final fields = Fields(payload);
    final revision = fields.count('revision');
    final delta = {
      for (final table in _tables.keys) table: fields.list(table, object),
    };
    for (final entry in delta.entries) {
      for (final row in entry.value) {
        final rowFields = Fields(row);
        rowFields.count('revision');
        if (entry.key == 'settings') {
          if (rowFields.required<String>('key') != 'filters') invalidResponse();
          final filter = Fields(rowFields.required<Json>('value'));
          filter.list(
            'models',
            (value) =>
                consoleModels.contains(value) ? value : invalidResponse(),
          );
          filter.choice(
            'buying',
            BuyingFilter.values.map((value) => value.name),
          );
          filter.choice(
            'order',
            ListingOrder.values.map((value) => value.name),
          );
          filter.required<bool>('boards');
          filter.required<bool>('ending');
          for (final key in ['max_price', 'max_total']) {
            final value = filter.nullable<num>(key);
            if (value != null && (!value.isFinite || value < 0)) {
              invalidResponse();
            }
          }
        } else {
          rowFields.required<String>('source');
          rowFields.required<String>('source_listing_id');
          if (!rowFields.required<bool>('deleted')) {
            if (entry.key == 'favorites') {
              SavedFavorite(row);
            } else {
              rowFields.required<String>('title');
            }
          }
        }
      }
    }
    if (revision < _revision) invalidResponse();
    for (final entry in delta.entries) {
      for (final row in entry.value) {
        _tables[entry.key]![entry.key == 'settings'
                ? row['key'] as String
                : stateKey(row)] =
            row;
      }
    }
    _revision = revision;
  }

  Future<void> _persist() {
    final snapshot = <String, Object?>{
      'revision': _revision,
      for (final entry in _tables.entries)
        entry.key: entry.value.values.toList(),
      'pending': _queue.toList(),
      'synced_at': lastSync?.toIso8601String(),
      'favorite_refresh_at': _lastRefresh?.toIso8601String(),
      'dismissed_new': _dismissedNew.toList(),
    };
    final written = _writing.then((_) => save(snapshot));
    _writing = written.then(
      (_) {
        localSaveFailed = false;
      },
      onError: (Object _, StackTrace _) {
        localSaveFailed = true;
        _notify();
      },
    );
    return written;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String favoriteStatus(Listing item, DateTime now) {
  if (item.status == 'ENDED' || (item.end != null && !item.end!.isAfter(now))) {
    return 'ENDED';
  }
  if (item.status == 'UNKNOWN' || isUnchecked(item, now)) return 'UNKNOWN';
  return 'ACTIVE';
}
