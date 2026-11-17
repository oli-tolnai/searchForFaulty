import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api/models.dart';
import 'listings.dart';
import 'notifications.dart';

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
      'fault_source': row['fault_source'] ?? 'condition',
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
    for (final table in [
      'favorites',
      'hidden',
      'settings',
      'watches',
      'alerts',
    ])
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
  String get currency =>
      (_view('settings')['currency']?['value'] as Json?)?['currency']
          as String? ??
      'EUR';
  ExchangeRate? exchangeRate;
  bool isFavorite(Listing item) =>
      _view('favorites')[listingKey(item)]?['deleted'] == false;
  bool isHidden(Listing item) =>
      _view('hidden')[listingKey(item)]?['deleted'] == false;
  bool isNew(Listing item) =>
      item.isNew && !_dismissedNew.contains(listingKey(item));

  Iterable<AuctionWatch> get watches =>
      _view('watches').values
          .where((row) => row['deleted'] == false)
          .map(AuctionWatch.new);
  Iterable<AlertRule> get alerts =>
      _view('alerts').values
          .where((row) => row['deleted'] == false)
          .map(AlertRule.new);

  AuctionWatch? watchFor(Listing item) {
    final row = _view('watches')[listingKey(item)];
    return row == null || row['deleted'] != false ? null : AuctionWatch(row);
  }

  Future<void> addWatch(Listing item, num threshold, int lead) => _add({
    'type': 'watch_add',
    'source': item.source,
    'source_listing_id': item.id,
    'listing': item.toJson(),
    'threshold': threshold,
    'lead_minutes': lead,
  });

  Future<void> updateWatch(AuctionWatch watch, num threshold, int lead) =>
      _add({
        'type': 'watch_update',
        'source': watch.source,
        'source_listing_id': watch.id,
        'threshold': threshold,
        'lead_minutes': lead,
      });

  Future<void> removeWatch(AuctionWatch watch) => _add({
    'type': 'watch_remove',
    'source': watch.source,
    'source_listing_id': watch.id,
  });

  Future<void> saveAlert(AlertRule? rule, Json values) => _add({
    ...values,
    'type': rule == null ? 'alert_add' : 'alert_update',
    'id': rule?.id ?? _newId(),
  });

  Future<void> removeAlert(AlertRule rule) =>
      _add({'type': 'alert_remove', 'id': rule.id});

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

  Future<void> setCurrency(String value) => _add({
    'type': 'setting_set',
    'key': 'currency',
    'value': {'currency': value},
  });

  void acceptExchangeRate(ExchangeRate rate) {
    exchangeRate = rate;
    changedLocally();
  }

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
      'op_id': _newId(),
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

  static String _newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

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
          final key = op['key'] as String;
          rows[key] = {'key': key, 'value': op['value']};
        case ('watches', 'watch_add'):
          final listing = object(op['listing']);
          final previous = rows[stateKey(op)];
          rows[stateKey(op)] = {
            'source': op['source'],
            'source_listing_id': op['source_listing_id'],
            'title': listing['title'],
            'url': listing['url'],
            'end_time': listing['end_time'],
            'last_bid': listing['currency'] == 'EUR'
                ? listing['current_bid']
                : null,
            'last_checked_at': listing['last_checked_at'],
            'status': previous?['notified_at'] != null ? 'notified' : 'active',
            'threshold': op['threshold'],
            'lead_minutes': op['lead_minutes'],
            'deleted': false,
          };
        case ('watches', 'watch_update'):
          final key = stateKey(op);
          if (rows[key] case final previous?
              when previous['deleted'] == false) {
            rows[key] = {
              ...previous,
              'threshold': op['threshold'],
              'lead_minutes': op['lead_minutes'],
            };
          }
        case ('watches', 'watch_remove'):
          final key = stateKey(op);
          if (rows[key] case final previous?) {
            rows[key] = {...previous, 'deleted': true};
          }
        case ('alerts', 'alert_add'):
        case ('alerts', 'alert_update'):
          final id = op['id'] as String;
          rows[id] = {...op, 'deleted': false};
        case ('alerts', 'alert_remove'):
          rows.remove(op['id']);
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
    final incomingRate = payload['exchange_rate'] == null
        ? null
        : ExchangeRate.fromJson(payload['exchange_rate']);
    final delta = {
      for (final table in _tables.keys)
        table:
            (table == 'watches' || table == 'alerts') &&
                !payload.containsKey(table)
            ? <
                Json
              >[] // Snapshots and webapp deployments from before notifications.
            : fields.list(table, object),
    };
    for (final entry in delta.entries) {
      for (final row in entry.value) {
        final rowFields = Fields(row);
        rowFields.count('revision');
        if (entry.key == 'settings') {
          final key = rowFields.choice('key', ['filters', 'currency']);
          final filter = Fields(rowFields.required<Json>('value'));
          if (key == 'currency') {
            filter.choice('currency', ['EUR', 'HUF']);
            continue;
          }
          filter.list(
            'models',
            (value) =>
                allDeviceModels.contains(value) ? value : invalidResponse(),
          );
          if (filter.json.containsKey('device_groups')) {
            final groups = filter.list(
              'device_groups',
              (value) =>
                  deviceGroups.contains(value) ? value : invalidResponse(),
            );
            if (groups.isEmpty || groups.toSet().length != groups.length) {
              invalidResponse();
            }
          }
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
        } else if (entry.key == 'alerts') {
          rowFields.required<String>('id');
          if (!rowFields.required<bool>('deleted')) AlertRule(row);
        } else {
          rowFields.required<String>('source');
          rowFields.required<String>('source_listing_id');
          if (!rowFields.required<bool>('deleted')) {
            if (entry.key == 'favorites') {
              SavedFavorite(row);
            } else if (entry.key == 'watches') {
              AuctionWatch(row);
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
        final key = switch (entry.key) {
          'settings' => row['key'] as String,
          'alerts' => row['id'] as String,
          _ => stateKey(row),
        };
        _tables[entry.key]![key] = row;
      }
    }
    _revision = revision;
    exchangeRate = incomingRate ?? exchangeRate;
  }

  Future<void> _persist() {
    final snapshot = <String, Object?>{
      'revision': _revision,
      'exchange_rate': exchangeRate?.toJson(),
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
