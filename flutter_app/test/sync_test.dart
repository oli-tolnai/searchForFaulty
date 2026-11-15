import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/responses.dart';

Json delta({
  int revision = 0,
  List<Json> favorites = const [],
  List<Json> hidden = const [],
  List<Json> settings = const [],
}) => {
  'revision': revision,
  'favorites': favorites,
  'hidden': hidden,
  'settings': settings,
};

void main() {
  test(
    'offline edits survive restart and resend the same operation ID',
    () async {
      final item = Listing.fromJson(listing());
      Json? disk;
      final offline = SharedState(
        readRemote: (_) async => throw const AppFailure('offline'),
        writeRemote: (_) async => throw const AppFailure('offline'),
        refreshRemote: () async => {},
        save: (snapshot) async {
          disk = snapshot;
        },
      );
      await offline.hide(item);
      expect(offline.isHidden(item), isTrue);
      expect(offline.pending, isTrue);
      final op = object((disk!['pending'] as List).single);
      offline.dispose();
      final restored = SharedState(
        restored: disk,
        readRemote: (_) async => delta(
          revision: 1,
          hidden: [
            {
              'source': item.source,
              'source_listing_id': item.id,
              'title': item.title,
              'revision': 1,
              'deleted': false,
            },
          ],
        ),
        writeRemote: (ops) async {
          expect(ops.single['op_id'], op['op_id']);
          return {
            'applied_op_ids': [op['op_id']],
          };
        },
        refreshRemote: () async => {},
        save: (_) async {},
      );
      expect(restored.isHidden(item), isTrue);
      await restored.sync();
      expect(restored.pending, isFalse);
      expect(restored.isHidden(item), isTrue);
      restored.dispose();
    },
  );

  test(
    'filter edits synchronize and are received by a second client',
    () async {
      Json? remote;
      Json saved = {};
      final filters = <String, Object?>{
        'models': ['PS5 Slim'],
        'max_price': 75,
        'max_total': null,
        'buying': 'both',
        'ending': true,
        'boards': false,
        'order': 'newest',
      };
      Future<Json> read(int _) async => remote == null
          ? delta()
          : delta(
              revision: 1,
              settings: [
                {'key': 'filters', 'value': remote, 'revision': 1},
              ],
            );
      final a = SharedState(
        readRemote: read,
        writeRemote: (ops) async {
          remote = object(ops.single['value']);
          return {
            'applied_op_ids': [ops.single['op_id']],
          };
        },
        refreshRemote: () async => {},
        save: (value) async {
          saved = value;
        },
      );
      final b = SharedState(
        readRemote: read,
        writeRemote: (_) async => {},
        refreshRemote: () async => {},
        save: (_) async {},
      );
      await a.setFilters(filters);
      await b.sync();
      expect(a.pending, isFalse);
      expect(saved['revision'], 1);
      expect(b.filters, filters);
      a.dispose();
      b.dispose();
    },
  );

  test('new tags disappear when opened or when starting another search', () {
    final a = Listing.fromJson(listing(isNew: true));
    final b = Listing.fromJson(listing(id: 'v1|456|0', isNew: true));
    final controller = SharedState(
      readRemote: (_) async => delta(),
      writeRemote: (_) async => {},
      refreshRemote: () async => {},
      save: (_) async {},
    );
    expect(controller.isNew(a), isTrue);
    controller.dismissNew(a);
    expect(controller.isNew(a), isFalse);
    expect(controller.isNew(b), isTrue);
    controller.searchedAgain([a, b]);
    expect(controller.isNew(b), isFalse);
    controller.dispose();
  });

  test(
    'saved favorites distinguish active, stale, ended and failed checks',
    () {
      expect(favoriteStatus(Listing.fromJson(listing()), testTime), 'ACTIVE');
      expect(
        favoriteStatus(
          Listing.fromJson(listing()),
          testTime.add(const Duration(hours: 2)),
        ),
        'UNKNOWN',
      );
      expect(
        favoriteStatus(Listing.fromJson(listing(end: testTime)), testTime),
        'ENDED',
      );
      expect(
        favoriteStatus(
          Listing.fromJson({...listing(), 'status': 'UNKNOWN'}),
          testTime,
        ),
        'UNKNOWN',
      );
    },
  );
}
