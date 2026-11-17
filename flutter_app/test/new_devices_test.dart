import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/listings.dart';
import 'package:flutter_app/listing_card.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/responses.dart';

void main() {
  test(
    'new groups and metadata survive offline serialization and remain filtered',
    () {
      for (final (group, type, model) in [
        ('switch', 'console', 'Switch V2'),
        ('steam_deck', 'console', 'Steam Deck OLED'),
        ('iphone', 'phone', 'iPhone 16e'),
        ('gpu', 'gpu', 'RTX 30'),
      ]) {
        final raw = listing(deviceGroup: group, type: type, model: model);
        if (group == 'iphone') raw['icloud_status'] = 'free_by_seller';
        final item = Listing.fromJson(raw);
        expect(modelsByDeviceGroup[group], contains(model));
        expect(inMainResults(item, mainboards: false), true);
        expect(
          inMainResults(
            Listing.fromJson({...raw, 'ships_to_hu': 'probably_no'}),
            mainboards: false,
          ),
          false,
        );
        final restored = SearchResult.fromJson(
          SearchResult.fromJson(search(known: [raw])).toCacheJson(),
        ).listings.single;
        expect(restored.deviceGroup, group);
        expect(
          restored.icloudStatus,
          group == 'iphone' ? 'free_by_seller' : 'unknown',
        );
      }
      expect(
        inMainResults(
          Listing.fromJson(
            listing(deviceGroup: 'iphone', type: 'icloud_locked'),
          ),
          mainboards: false,
        ),
        false,
      );
    },
  );

  testWidgets(
    'opening description verifies shipping and moves a hidden Switch into the main list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final result = SearchResult.fromJson(
        search(
          unknown: [
            listing(
              title: 'Vizsgált Switch készülék',
              model: 'Switch V2',
              deviceGroup: 'switch',
              shipsToHu: 'probably_no',
            ),
          ],
        ),
      );
      var calls = 0;
      SearchResult? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            initial: result,
            clock: () => testTime,
            search: (_) async => result,
            saveResult: (value) async {
              saved = value;
            },
            loadDetails: (_) async {
              calls++;
              return ListingDetails.fromJson({
                ...details,
                'ships_to_hu': 'yes',
                'shipping_cost': '5',
                'shipping_currency': 'EUR',
                'icloud_status': 'unknown',
              });
            },
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Switch'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Vizsgált Switch készülék'), findsNothing);
      await tester.tap(
        find.text('1 · Valószínűleg nem szállít Magyarországra'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vizsgált Switch készülék'), findsOneWidget);
      await tester.tap(find.text('Leírás'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Vizsgált Switch készülék'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Vizsgált Switch készülék'), findsOneWidget);
      expect(saved!.allListings.single.shipsToHu, 'yes');
      expect(saved!.allListings.single.total, '80.00');
      expect(
        find.text('Ismeretlen szállítási díj – a hirdetésben ellenőrizd'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'iPhone cards distinguish seller-claimed free status from unknown',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget card(String status) => ListingCard(
        item: Listing.fromJson({
          ...listing(
            title: 'iPhone kártya $status',
            deviceGroup: 'iphone',
            type: 'phone',
            model: 'iPhone 13',
          ),
          'icloud_status': status,
        }),
        now: testTime,
        loadDetails: (_) async => ListingDetails.fromJson(details),
        onUnavailable: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [card('free_by_seller'), card('unknown')]),
          ),
        ),
      );
      expect(find.text('iCloud-mentes (az eladó szerint)'), findsOneWidget);
      expect(
        find.text(
          'Az iCloud-zár állapota nem ismert – vásárlás előtt kérdezd meg az eladót',
        ),
        findsOneWidget,
      );
    },
  );
}
