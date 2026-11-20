import 'fixtures/ui_actions.dart';

import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/group_results.dart';
import 'package:flutter_app/search_filters.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/responses.dart';

PingResult config() => PingResult.fromJson({
  'version': 'test',
  'server_time': testTime.toIso8601String(),
  'daily_api_calls': 400,
  'search_config': {
    'country_count': 27,
    'groups': {
      for (final group in deviceGroups)
        group: {
          'query_count': 1,
          'estimated_calls': group == 'consoles'
              ? 60
              : group == 'controllers'
              ? 110
              : 27,
        },
    },
  },
});

void main() {
  testWidgets('a saved search filter opens an editable new alert preset', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final shared = SharedState(
      readRemote: (_) async => throw const AppFailure('offline'),
      writeRemote: (_) async => throw const AppFailure('offline'),
      refreshRemote: () async => {},
      save: (_) async {},
    );
    addTearDown(shared.dispose);
    await shared.setSearchFilter(
      'switch',
      GroupSearchFilter({
        'min_price': 10,
        'include_keywords': ['drift'],
        'exclude_banned': true,
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          shared: shared,
          clock: () => testTime,
          search: (_) async => SearchResult.fromJson(search()),
          loadDetails: (_) async => ListingDetails.fromJson(details),
        ),
      ),
    );

    await selectCategory(tester, 'Switch');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Értesítés ilyen találatokról'));
    await tester.pumpAndSettle();
    expect(find.text('Új értesítési szabály'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Név'),
      'Driftes Switch',
    );
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Min. vételár vagy aktuális licit (EUR)',
      ),
      '20',
    );
    await tester.tap(find.text('Mentés'));
    await tester.pumpAndSettle();
    expect(shared.alerts.single.name, 'Driftes Switch');
    expect(shared.alerts.single.groups, ['switch']);
    expect(shared.alerts.single.includeKeywords, ['drift']);
    expect(shared.alerts.single.excludeBanned, true);
    expect(shared.alerts.single.advanced['min_price'], 20);
  });
  test('refreshing one group and restarting preserves other groups, empty results, and partial status', () {
    final a = SearchResult.fromJson(
      search(known: [listing(title: 'Korábbi konzol')]),
    );
    final b = SearchResult.fromJson(
      search(
        status: 'partial',
        known: [
          listing(
            deviceGroup: 'gpu',
            type: 'gpu',
            model: 'RTX 30',
            title: 'Megtartott GPU',
          ),
        ],
      ),
    );
    final groups = GroupResults({'consoles': a, 'gpu': b});
    groups.groups.addAll(
      GroupResults.split(SearchResult.fromJson(search()), ['consoles']),
    );
    final restarted = GroupResults.fromJson(groups.toJson());
    expect(restarted.groups['consoles']!.allListings, isEmpty);
    expect(restarted.groups['gpu']!.allListings.single.title, 'Megtartott GPU');
    expect(restarted.groups['gpu']!.status, 'partial');
    restarted.expire(testTime.add(const Duration(hours: 6)));
    expect(restarted.groups['gpu']!.allListings, isEmpty);
    expect(restarted.groups['gpu']!.searchedAt, testTime);
  });
  test('each local filter has immediate independent effects and preserves unknown shipping totals', () {
    final item = Listing.fromJson(
      listing(
        title: 'PS5 Slim Drift',
        price: '75',
        shipping: '5',
        total: '80',
        end: testTime.add(const Duration(hours: 12)),
      ),
    );
    final cases = <String, Object?>{
      'models': ['PS5 Pro'],
      'min_price': 76,
      'max_price': 74,
      'max_total_price': 79,
      'buying_options': 'fixed',
      'ending_hours': 6,
      'countries': ['FR'],
      'include_keywords': ['kaputt'],
      'exclude_keywords': ['DRIFT'],
    };
    for (final entry in cases.entries) {
      expect(
        GroupSearchFilter({entry.key: entry.value}).matches(item, testTime),
        false,
        reason: entry.key,
      );
    }
    expect(
      GroupSearchFilter({'max_total_price': 1})
          .matches(Listing.fromJson(listing()), testTime),
      true,
    );
    expect(
      GroupSearchFilter({'ending_hours': 6})
          .matches(Listing.fromJson(listing()), testTime),
      true,
    );
    expect(
      GroupSearchFilter({
        'exclude_banned': true,
      }).matches(Listing.fromJson({...listing(), 'is_banned': true}), testTime),
      false,
    );
    expect(
      GroupSearchFilter({'exclude_possibly_not_faulty': true}).matches(
        Listing.fromJson({...listing(), 'possibly_not_faulty': true}),
        testTime,
      ),
      false,
    );
    expect(
      GroupSearchFilter({'include_title_faults': false}).matches(
        Listing.fromJson({...listing(), 'fault_source': 'title'}),
        testTime,
      ),
      false,
    );
    final phone = Listing.fromJson(
      listing(type: 'phone', deviceGroup: 'iphone', model: 'iPhone 13'),
    );
    expect(
      GroupSearchFilter({'only_icloud_free': true}).matches(phone, testTime),
      false,
    );
    expect(
      GroupSearchFilter({'hide_unknown_icloud': true}).matches(phone, testTime),
      false,
    );
    expect(
      GroupSearchFilter({'gpu_vendor': 'AMD'}).matches(
        Listing.fromJson(
          listing(type: 'gpu', deviceGroup: 'gpu', model: 'RTX 30'),
        ),
        testTime,
      ),
      false,
    );
    expect(
      GroupSearchFilter({'include_third_party': true}).matches(
        Listing.fromJson(
          listing(type: 'third_party', deviceGroup: 'controllers'),
        ),
        testTime,
      ),
      true,
    );
    expect(
      GroupSearchFilter({'include_mainboards': true})
          .matches(Listing.fromJson(listing(type: 'mainboard')), testTime),
      true,
    );
    expect(
      GroupSearchFilter({'seller': 'must disappear'}).values
          .containsKey('seller'),
      false,
    );
  });
  test('per-group filters and visible tabs merge through shared state without changing another group', () async {
    final shared = SharedState(
      readRemote: (_) async => throw const AppFailure('offline'),
      writeRemote: (_) async => throw const AppFailure('offline'),
      refreshRemote: () async => {},
      save: (_) async {},
    );
    addTearDown(shared.dispose);
    await shared.setSearchFilter(
      'iphone',
      GroupSearchFilter({'min_price': 10, 'only_icloud_free': true}),
    );
    await shared.setSearchFilter(
      'gpu',
      GroupSearchFilter({'gpu_vendor': 'AMD'}),
    );
    await shared.setVisibleSearchGroups(['iphone', 'gpu']);
    expect(shared.searchFilter('iphone').amount('min_price'), 10);
    expect(shared.searchFilter('gpu').values['gpu_vendor'], 'AMD');
    expect(shared.visibleSearchGroups, ['iphone', 'gpu']);
    final preset = shared.searchFilter('iphone').alert('iphone');
    expect(preset['device_groups'], ['iphone']);
    expect(preset['only_icloud_free'], true);
  });
  testWidgets(
    'group search keeps GPU results and confirmation protects expensive aggregate refresh',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final groups = GroupResults({
        'gpu': SearchResult.fromJson(
          search(
            known: [
              listing(
                deviceGroup: 'gpu',
                type: 'gpu',
                title: 'Megőrzött kártya',
                model: 'RTX 30',
              ),
            ],
          ),
        ),
      });
      final requests = <Set<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            initialGroups: groups,
            clock: () => testTime,
            loadConfig: () async => config(),
            search: (selected) async {
              requests.add(selected);
              return SearchResult.fromJson(search());
            },
            loadDetails: (_) async => ListingDetails.fromJson(details),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-search')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('278'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('400'), findsOneWidget);
      expect(requests, isEmpty);
      await tester.tap(find.text('Mégse'));
      await tester.pumpAndSettle();
      await selectCategory(tester, 'Switch');
      await tester.pumpAndSettle();
      expect(find.text('Ebben a csoportban még nem kerestél'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-search')));
      await tester.pumpAndSettle();
      expect(requests, [
        {'switch'},
      ]);
      expect(
        groups.groups['gpu']!.allListings.single.title,
        'Megőrzött kártya',
      );
    },
  );
  testWidgets(
    'phone filter opens a bottom sheet and desktop uses a side panel without search calls',
    (tester) async {
      for (final width in [390.0, 1280.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1400));
        var searches = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: SearchScreen(
              key: ValueKey(width),
              clock: () => testTime,
              initial: SearchResult.fromJson(
                search(
                  known: [
                    listing(
                      title: 'Olcsó készülék',
                      price: '30',
                      shipping: '0',
                      total: '30',
                    ),
                    listing(
                      id: 'two',
                      title: 'Drága készülék',
                      price: '100',
                      shipping: '0',
                      total: '100',
                    ),
                  ],
                ),
              ),
              search: (_) async {
                searches++;
                return SearchResult.fromJson(search());
              },
              loadDetails: (_) async => ListingDetails.fromJson(details),
            ),
          ),
        );
        await selectCategory(tester, 'Konzol');
        await tester.pumpAndSettle();
        await openFilters(tester);
        await tester.pumpAndSettle();
        expect(
          find.byType(BottomSheet),
          width < 1000 ? findsOneWidget : findsNothing,
        );
        final field = find.widgetWithText(TextFormField, 'Ár eddig (EUR)');
        await tester.enterText(field, '50');
        await tester.pumpAndSettle();
        expect(searches, 0);
        if (width < 1000) {
          if (find.byTooltip('Szűrők bezárása').evaluate().isNotEmpty) {
            await tester.tap(find.byTooltip('Szűrők bezárása'));
          }
          await tester.pumpAndSettle();
        }
        expect(find.text('Drága készülék'), findsNothing);
        expect(find.text('Olcsó készülék'), findsOneWidget);
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'category picker replaces horizontal tabs and retains group selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            clock: () => testTime,
            search: (_) async => SearchResult.fromJson(search()),
            loadDetails: (_) async => ListingDetails.fromJson(details),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await selectCategory(tester, 'Switch');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('run-search')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Switch').hitTestable(), findsOneWidget);
      expect(
        find.text('Ebben a csoportban még nem kerestél').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
