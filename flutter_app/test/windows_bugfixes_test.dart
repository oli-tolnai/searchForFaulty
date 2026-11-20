import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_app/app_theme.dart';
import 'package:flutter_app/external_search.dart';
import 'package:flutter_app/group_results.dart';
import 'package:flutter_app/listing_card.dart';
import 'package:flutter_app/search_filter_panel.dart';
import 'package:flutter_app/search_filters.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/responses.dart';
import 'fixtures/ui_actions.dart';

SharedState offline({Json? initial, Future<void> Function(Json)? save}) =>
    SharedState(
      restored: initial,
      readRemote: (_) async => throw const AppFailure('offline'),
      writeRemote: (_) async => throw const AppFailure('offline'),
      refreshRemote: () async => {},
      save: save ?? (_) async {},
    );

void main() {
  test('aggregate estimates sum every visible group including supplementary searches', () {
    expect(estimateSearchCalls(deviceGroups), 465);
    for (final group in deviceGroups) {
      expect(
        estimateSearchCalls(deviceGroups),
        greaterThanOrEqualTo(estimateSearchCalls([group])!),
      );
    }
    final sum = deviceGroups.fold(
      0,
      (sum, group) => sum + estimateSearchCalls([group])!,
    );
    expect(estimateSearchCalls(deviceGroups), sum);
    expect(
      estimateSearchCalls([
        'consoles',
        'gpu',
      ], configured: (g) => g == 'consoles' ? 80 : null),
      134,
    );
  });
  test(
    'aggregate filters persist independently and exclude group-only settings',
    () async {
      Json? saved;
      final a = offline(save: (value) async => saved = value);
      await a.setSearchFilter('consoles', GroupSearchFilter({'max_price': 90}));
      await a.setSearchFilter(
        'all',
        GroupSearchFilter({
          'max_price': 25,
          'models': ['PS5 Slim'],
          'include_mainboards': true,
        }),
      );
      expect(a.searchFilter('all').strings('models'), isEmpty);
      expect(a.searchFilter('all').flag('include_mainboards'), false);
      final b = offline(initial: saved);
      expect(b.searchFilter('all').amount('max_price'), 25);
      expect(b.searchFilter('consoles').amount('max_price'), 90);
      a.dispose();
      b.dispose();
    },
  );
  for (final width in [390.0, 1440.0]) {
    testWidgets('aggregate price filter affects all groups at width $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = offline();
      addTearDown(s.dispose);
      await s.setSearchFilter(
        'controllers',
        GroupSearchFilter({'max_price': 1}),
      );
      final groups = GroupResults({
        for (final g in ['consoles', 'controllers'])
          g: SearchResult.fromJson(
            search(
              known: [
                listing(
                  id: '$g-cheap',
                  title: '$g olcsó',
                  price: '20',
                  deviceGroup: g,
                  type: g == 'consoles' ? 'console' : 'controller',
                ),
                listing(
                  id: '$g-expensive',
                  title: '$g drága',
                  price: '80',
                  deviceGroup: g,
                  type: g == 'consoles' ? 'console' : 'controller',
                ),
              ],
            ),
          ),
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Ui.theme,
          home: SearchScreen(
            shared: s,
            clock: () => testTime,
            initialGroups: groups,
            search: (_) async => SearchResult.fromJson(search()),
            loadDetails: (_) async => ListingDetails.fromJson(details),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('controllers olcsó'), findsOneWidget);
      await openFilters(t);
      expect(find.text('Kategória szűrői'), findsNothing);
      expect(find.text('Modell'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Ár eddig (EUR)'),
        '30',
      );
      await t.pumpAndSettle();
      expect(s.searchFilter('all').amount('max_price'), 30);
      expect(s.searchFilter('controllers').amount('max_price'), 1);
      if (width < 1100) {
        await t.tap(find.text('2 találat mutatása'));
        await t.pumpAndSettle();
      }
      expect(find.text('consoles olcsó'), findsOneWidget);
      expect(find.text('controllers olcsó'), findsOneWidget);
      expect(find.text('consoles drága'), findsNothing);
      expect(find.text('controllers drága'), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets(
      'advanced settings survive 20 open-close cycles at width $width',
      (t) async {
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var filter = GroupSearchFilter();
        await t.pumpWidget(
          MaterialApp(
            theme: Ui.theme,
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: width == 1440 ? 272 : width,
                  child: SearchFilterPanel(
                    group: 'all',
                    read: () => filter,
                    change: (key, value) => filter = filter.change(key, value),
                    close: () {},
                    clear: () {},
                    count: () => 0,
                    desktop: width == 1440,
                  ),
                ),
              ),
            ),
          ),
        );
        final scroll = find.byType(Scrollable).first;
        final advanced = find.text('További beállítások');
        for (var i = 0; i < 20; i++) {
          await t.scrollUntilVisible(advanced, 200, scrollable: scroll);
          await t.tap(advanced);
          await t.pumpAndSettle();
          final keyword = find.widgetWithText(
            TextFormField,
            'A cím tartalmazza bármelyiket',
          );
          await t.scrollUntilVisible(keyword, 200, scrollable: scroll);
          await t.enterText(keyword, 'teszt $i');
          await t.pumpAndSettle();
          expect(filter.strings('include_keywords'), ['teszt $i']);
          expect(
            find.widgetWithText(DropdownButtonFormField<Object>, 'Rendezés'),
            findsNothing,
          );
          await t.scrollUntilVisible(advanced, -250, scrollable: scroll);
          await t.tap(advanced);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
        }
      },
    );
  }
  for (final options in <List<String>?>[
    ['AUCTION'],
    ['FIXED_PRICE'],
    ['AUCTION', 'FIXED_PRICE'],
    ['FIXED_PRICE', 'BEST_OFFER'],
    ['AUCTION', 'BEST_OFFER'],
    null,
  ]) {
    test('buying option filters use explicit flags: $options', () {
      final raw = listing(end: testTime.add(const Duration(hours: 1)));
      if (options == null) {
        raw.remove('buying_options');
      } else {
        raw['buying_options'] = options;
      }
      final item = Listing.fromJson(raw);
      expect(
        GroupSearchFilter({'buying_options': 'both'}).matches(item, testTime),
        true,
      );
      expect(
        GroupSearchFilter({'buying_options': 'auction'})
            .matches(item, testTime),
        options?.contains('AUCTION') ?? false,
      );
      expect(
        GroupSearchFilter({'buying_options': 'fixed'}).matches(item, testTime),
        options?.contains('FIXED_PRICE') ?? false,
      );
    });
  }
  testWidgets('combined auction and buy-now listing is labeled on card', (
    t,
  ) async {
    final raw = listing(end: testTime.add(const Duration(hours: 1)))
      ..['buying_options'] = ['AUCTION', 'FIXED_PRICE'];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingCard(
            item: Listing.fromJson(raw),
            now: testTime,
            loadDetails: (_) async => ListingDetails.fromJson(details),
            onUnavailable: () {},
            unavailable: false,
          ),
        ),
      ),
    );
    expect(find.textContaining('Aukció + Azonnali vétel'), findsOneWidget);
  });
  testWidgets(
    'aggregate confirmation and requests include all visible groups, not legacy selection',
    (t) async {
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = offline();
      addTearDown(s.dispose);
      await s.setVisibleSearchGroups(['consoles', 'controllers']);
      await s.setSelectedSearchGroups(['consoles']);
      final requests = <Set<String>>[];
      await t.pumpWidget(
        MaterialApp(
          theme: Ui.theme,
          home: SearchScreen(
            shared: s,
            initial: SearchResult.fromJson(search(known: [listing()])),
            clock: () => testTime,
            search: (groups) async {
              requests.add(groups);
              return SearchResult.fromJson(search());
            },
            loadDetails: (_) async => ListingDetails.fromJson(details),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Keresés · kb. 168 hívás'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('run-search')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('168'),
        ),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await t.tap(find.text('Frissítés'));
      await t.pumpAndSettle();
      expect(requests, [
        {'consoles'},
        {'controllers'},
      ]);
      expect(t.takeException(), isNull);
    },
  );
}
