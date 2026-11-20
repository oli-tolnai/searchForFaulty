import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_app/listing_card.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/responses.dart';
import 'fixtures/ui_actions.dart';

void main() {
  Future<void> screen(WidgetTester tester, SearchScreen page) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1350));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: page));
  }

  testWidgets(
    'controller selection is synced and only selected groups are requested',
    (tester) async {
      final response = SearchResult.fromJson(
        search(
          unknown: [
            listing(
              id: 'v1|10|0',
              title: 'Scuf hibás kontroller',
              type: 'controller',
              deviceGroup: 'controllers',
              model: 'DualSense (Scuf)',
              isScuf: true,
            ),
            listing(
              id: 'v1|11|0',
              title: 'Utángyártott kontroller',
              type: 'third_party',
              deviceGroup: 'controllers',
            ),
            listing(
              id: 'v1|12|0',
              title: 'Külön töltőállomás',
              type: 'not_controller',
              deviceGroup: 'controllers',
            ),
          ],
        ),
      );
      final shared = SharedState(
        readRemote: (_) async => throw const AppFailure('offline'),
        writeRemote: (_) async => throw const AppFailure('offline'),
        refreshRemote: () async => {},
        save: (_) async {},
      );
      addTearDown(shared.dispose);
      Set<String>? requested;
      await screen(
        tester,
        SearchScreen(
          clock: () => testTime,
          shared: shared,
          search: (groups) async {
            requested = groups;
            return response;
          },
          loadDetails: (_) async => ListingDetails.fromJson(details),
        ),
      );
      await selectCategory(tester, 'Kontroller');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-search')));
      await tester.pumpAndSettle();
      expect(requested, {'controllers'});
      await openFilters(tester);
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      expect(find.text('PS5 Slim'), findsNothing);
      expect(find.text('DualSense Edge'), findsOneWidget);
      expect(find.text('Xbox Elite (sorozat nem ismert)'), findsOneWidget);
      await tester.tap(find.text('DualSense'));
      await tester.pumpAndSettle();
      expect(shared.searchFilter('controllers').strings('models'), [
        'DualSense',
      ]);
      if (find.byTooltip('Szűrők bezárása').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Szűrők bezárása'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Scuf hibás kontroller'), findsOneWidget);
      await openListing(tester, title: 'Scuf hibás kontroller');
      expect(find.text('Scuf'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Utángyártott kontroller'), findsNothing);
      expect(find.text('Külön töltőállomás'), findsNothing);
      await openHidden(tester, 'Harmadik féltől származó kontroller', count: 1);
      await tester.pumpAndSettle();
      expect(find.text('Utángyártott kontroller'), findsOneWidget);
      expect(find.text('Külön töltőállomás'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await openHidden(
        tester,
        'Nem kontroller (alkatrész vagy tartozék)',
        count: 1,
      );
      await tester.pumpAndSettle();
      expect(find.text('Külön töltőállomás'), findsOneWidget);
    },
  );

  testWidgets('a custom DualSense card shows the Egyedi badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListingCard(
                item: Listing.fromJson(
                  listing(
                    title: 'Ps5 Kingcontroller',
                    type: 'controller',
                    model: 'DualSense (Egyedi)',
                    deviceGroup: 'controllers',
                  ),
                ),
                now: testTime,
                loadDetails: (_) async => ListingDetails.fromJson(details),
                onUnavailable: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await openListing(tester);
    expect(find.text('Egyedi'), findsOneWidget);
  });

  testWidgets(
    'title fault provenance survives caching and appears on the card',
    (tester) async {
      final raw = listing(title: 'PS5 Slim Konsole defekt')
        ..['fault_source'] = 'title';
      final original = SearchResult.fromJson(search(unknown: [raw]));
      final restored = SearchResult.fromJson(original.toCacheJson());
      final item = restored.unknownShipping.single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ListingCard(
                  item: item,
                  now: testTime,
                  loadDetails: (_) async => ListingDetails.fromJson(details),
                  onUnavailable: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await openListing(tester);
      expect(
        find.text('Használtként hirdetve – a hiba a címből derül ki'),
        findsOneWidget,
      );
    },
  );

  testWidgets('hidden entries stay out of both normal and grouped results', (
    tester,
  ) async {
    final result = SearchResult.fromJson(
      search(
        unknown: [
          listing(title: 'Látható konzol'),
          listing(
            id: 'v1|456|0',
            shipsToHu: 'no',
            title: 'Elrejtett belföldi konzol',
          ),
        ],
      ),
    );
    final controller = SharedState(
      readRemote: (_) async => throw const AppFailure('offline'),
      writeRemote: (_) async => throw const AppFailure('offline'),
      refreshRemote: () async => {},
      save: (_) async {},
    );
    await controller.hide(result.unknownShipping.last);
    await screen(
      tester,
      SearchScreen(
        initial: result,
        clock: () => testTime,
        shared: controller,
        search: (_) async => result,
        loadDetails: (_) async => ListingDetails.fromJson(details),
      ),
    );
    expect(find.text('Látható konzol'), findsOneWidget);
    expect(find.text('Elrejtett belföldi konzol'), findsNothing);
    expect(
      find.widgetWithText(ExpansionTile, 'Rejtett tételek (0)'),
      findsOneWidget,
    );
    expect(find.text('Elrejtett belföldi konzol'), findsNothing);
    await tester.tap(find.text('Beállítások'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elrejtett hirdetések'));
    await tester.pumpAndSettle();
    expect(find.text('Elrejtett belföldi konzol'), findsOneWidget);
  });

  testWidgets('ships-no and other hidden types open in separate groups', (
    tester,
  ) async {
    final result = SearchResult.fromJson(
      search(
        unknown: [
          listing(title: 'Bizonytalan szállítás', shipsToHu: 'unknown'),
          listing(id: 'v1|2|0', title: 'Belföldi konzol', shipsToHu: 'no'),
          listing(
            id: 'v1|3|0',
            title: 'Régi modell',
            type: 'unsupported_model',
          ),
          listing(id: 'v1|4|0', title: 'Üres doboz', type: 'not_console'),
          listing(id: 'v1|5|0', title: 'Donor alaplap', type: 'mainboard'),
        ],
      ),
    );
    await screen(
      tester,
      SearchScreen(
        initial: result,
        clock: () => testTime,
        search: (_) async => result,
        loadDetails: (_) async => ListingDetails.fromJson(details),
      ),
    );
    expect(find.text('Bizonytalan szállítás'), findsNothing);
    for (final (count, group, item) in [
      (2, 'Valószínűleg nem szállít Magyarországra', 'Belföldi konzol'),
      (1, 'Nem támogatott modell', 'Régi modell'),
      (1, 'Nem konzol', 'Üres doboz'),
      (1, 'Alaplap', 'Donor alaplap'),
    ]) {
      expect(find.text(item), findsNothing);
      await openHidden(tester, group, count: count);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('hidden-group-heading')))
            .data,
        group,
      );
      expect(find.text(item), findsOneWidget);
      expect(
        find.text('Bizonytalan szállítás'),
        count == 2 ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    expect(find.text('Bizonytalan szállítás'), findsNothing);
  });

  testWidgets(
    'cards show shipping and totals only when known and load an expandable description',
    (tester) async {
      var requests = 0;
      await tester.binding.setSurfaceSize(const Size(850, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ListingCard(
                  item: Listing.fromJson(listing(shipping: '12', total: '87')),
                  now: testTime,
                  loadDetails: (_) async {
                    requests++;
                    return ListingDetails.fromJson(details);
                  },
                  onUnavailable: () {},
                ),
                ListingCard(
                  item: Listing.fromJson(listing(id: 'v1|456|0')),
                  now: testTime,
                  loadDetails: (_) async => ListingDetails.fromJson(details),
                  onUnavailable: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await openListing(tester);
      expect(find.text('Teljes ár'), findsOneWidget);
      expect(find.text('87 €'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListingCard).last);
      await tester.pumpAndSettle();
      expect(find.text('Teljes ár'), findsNothing);
      expect(find.text('Nem ismert'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await openListing(tester);
      expect(requests, 0);
      await description(tester);
      expect(requests, 1);
      expect(find.text('Az eladó megjegyzése az állapotról'), findsOneWidget);
      expect(find.text('Defektes Laufwerk'), findsOneWidget);
      expect(find.text('Originalverpackt mit Zubehör'), findsOneWidget);
      expect(find.text('Google Fordító megnyitása'), findsOneWidget);
      expect(
        translationLink('é & ${'🎮' * 4500}')
            .queryParameters['text']!
            .runes
            .length,
        4500,
      );
    },
  );

  testWidgets('listing_not_found adds a closed listing marker', (tester) async {
    var unavailable = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListingCard(
              item: Listing.fromJson(listing()),
              now: testTime,
              loadDetails: (_) async => throw const AppFailure(
                'A hirdetés már nem elérhető',
                code: 'listing_not_found',
              ),
              onUnavailable: () => unavailable = true,
            ),
          ),
        ),
      ),
    );
    await openListing(tester);
    await description(tester);
    expect(unavailable, isTrue);
    expect(find.text('A hirdetés már nem elérhető'), findsOneWidget);
  });

  testWidgets('partial run is labeled and country errors expand', (
    tester,
  ) async {
    final result = SearchResult.fromJson(
      search(
        status: 'partial',
        countries: [
          {
            'country': 'DE',
            'status': 'partial',
            'queries': [
              {
                'query': 'ps5',
                'status': 'error',
                'error': 'Időtúllépés',
                'warnings': [],
                'count': 0,
              },
            ],
          },
        ],
      ),
    );
    await screen(
      tester,
      SearchScreen(
        clock: () => testTime,
        search: (_) async => result,
        loadDetails: (_) async => ListingDetails.fromJson(details),
      ),
    );
    await selectCategory(tester, 'Konzol');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('run-search')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Részleges keresés'), findsOneWidget);
    await tester.tap(find.text('Keresés részletei'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Németország ·'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Németország'), findsOneWidget);
    expect(find.textContaining('Időtúllépés'), findsOneWidget);
  });

  testWidgets('auction disappears exactly at expiration', (tester) async {
    final start = tester.binding.clock.now();
    DateTime now() =>
        testTime.add(tester.binding.clock.now().difference(start));
    final result = SearchResult.fromJson(
      search(
        unknown: [
          listing(
            title: 'Lejáró tesztaukció',
            end: testTime.add(const Duration(milliseconds: 350)),
          ),
        ],
      ),
    );
    await screen(
      tester,
      SearchScreen(
        initial: result,
        clock: now,
        search: (_) async => result,
        loadDetails: (_) async => ListingDetails.fromJson(details),
      ),
    );
    expect(find.text('Lejáró tesztaukció'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 349));
    expect(find.text('Lejáró tesztaukció'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Lejáró tesztaukció'), findsNothing);
  });

  testWidgets(
    'offline results are marked and listings beyond the freshness limit are hidden',
    (tester) async {
      final result = SearchResult.fromJson(
        search(
          unknown: [
            listing(
              title: 'Régebben ellenőrzött',
              checkedAt: testTime.subtract(const Duration(hours: 2)),
            ),
            listing(
              id: 'v1|2|0',
              title: 'Túl régi',
              checkedAt: testTime.subtract(const Duration(hours: 6)),
            ),
          ],
        ),
      );
      await screen(
        tester,
        SearchScreen(
          initial: result,
          loadConfig: () async =>
              throw const AppFailure('A webapp nem érhető el.'),
          clock: () => testTime,
          search: (_) async => result,
          loadDetails: (_) async => ListingDetails.fromJson(details),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline – korábban mentett eredmény'), findsOneWidget);
      expect(find.text('Nem ellenőrzött'), findsOneWidget);
      expect(find.text('Túl régi'), findsNothing);
    },
  );
}
