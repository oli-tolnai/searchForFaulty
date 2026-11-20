import 'fixtures/ui_actions.dart';

import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_app/currency.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_app/watch_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/responses.dart';

const rateJson = {
  'eur_huf': 400.0,
  'date': '2026-11-17',
  'source': 'ECB',
  'stale': false,
};

void main() {
  test('HUF amounts round and group, stale rates work, and a missing rate uses EUR', () {
    final display = MoneyDisplay(
      'HUF',
      ExchangeRate.fromJson({...rateJson, 'eur_huf': 392.15, 'stale': true}),
    );
    expect(display.format('115.567', 'EUR'), '45 320 Ft');
    expect(display.format(null, 'EUR'), 'Nem ismert');
    expect(display.format('123', 'GBP'), 'Nem ismert');
    expect(
      display.rateLabel,
      '1 EUR = 392,15 Ft (ECB, 2026. 11. 17.) · korábbi árfolyam',
    );
    const unavailable = MoneyDisplay('HUF', null);
    expect(unavailable.huf, false);
    expect(unavailable.format('12', 'EUR'), '12 €');
    expect(unavailable.rateLabel, contains('nem ismert'));
  });

  test('currency sync applies a remote preference and persists a usable cached rate', () async {
    Json? stored;
    final state = SharedState(
      readRemote: (_) async => {
        'revision': 1,
        'favorites': [],
        'hidden': [],
        'watches': [],
        'alerts': [],
        'settings': [
          {
            'key': 'currency',
            'value': {'currency': 'HUF'},
            'revision': 1,
          },
        ],
        'exchange_rate': rateJson,
      },
      writeRemote: (_) async => {},
      refreshRemote: () async => {},
      save: (json) async {
        stored = json;
      },
    );
    await state.sync();
    expect(state.currency, 'HUF');
    expect(state.exchangeRate?.eurHuf, 400);
    expect(stored?['exchange_rate'], rateJson);
    state.dispose();
  });

  testWidgets(
    'tapping a price updates all card amounts and keeps synchronized filters in EUR',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = SharedState(
        readRemote: (_) async => throw const AppFailure('offline'),
        writeRemote: (_) async => throw const AppFailure('offline'),
        refreshRemote: () async => {},
        save: (_) async {},
      );
      addTearDown(state.dispose);
      final result = SearchResult.fromJson({
        ...search(
          known: [listing(shipping: '12', total: '87')],
        ),
        'exchange_rate': rateJson,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            initial: result,
            shared: state,
            clock: () => testTime,
            search: (_) async => result,
            loadDetails: (_) async => ListingDetails.fromJson(details),
          ),
        ),
      );
      await selectCategory(tester, 'Konzol');
      await tester.pumpAndSettle();
      await openFilters(tester);
      await tester.pumpAndSettle();
      Finder amount(String label) => find.widgetWithText(
        TextFormField,
        '$label (${state.currency == 'HUF' ? 'Ft' : 'EUR'})',
      );
      final maxPrice = amount('Ár eddig');

      await tester.enterText(maxPrice, '100');
      await tester.pumpAndSettle();
      expect(find.text('87 €'), findsOneWidget);
      await openListing(tester);
      expect(find.text('75 €'), findsOneWidget);
      await tester.tap(find.text('75 €'));
      await tester.pumpAndSettle();
      expect(state.currency, 'HUF');
      expect(find.text('30 000 Ft'), findsOneWidget);
      expect(find.text('4 800 Ft'), findsOneWidget);
      expect(find.text('34 800 Ft'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: amount('Ár eddig'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '40 000',
      );
      expect(state.searchFilter('consoles').amount('max_price'), 100);

      await tester.enterText(amount('Max. teljes ár'), '36 001');
      await tester.pumpAndSettle();
      expect(state.searchFilter('consoles').amount('max_total_price'), 90.0025);
      await openListing(tester);
      await tester.tap(find.text('4 800 Ft'));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(state.currency, 'EUR');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: amount('Max. teljes ár'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '90',
      );
      expect(state.searchFilter('consoles').amount('max_total_price'), 90.0025);
      await openListing(tester);
      expect(find.text('12 €'), findsOneWidget);
    },
  );

  testWidgets('watch threshold is entered in HUF and returned in EUR', (
    tester,
  ) async {
    WatchTerms? terms;
    final display = MoneyDisplay('HUF', ExchangeRate.fromJson(rateJson));
    await tester.pumpWidget(
      MaterialApp(
        home: MoneyScope(
          display: display,
          toggle: null,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  terms = await editWatchTerms(context, null);
                },
                child: const Text('Figyelés'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Figyelés'));
    await tester.pumpAndSettle();
    expect(find.text('Határár (Ft)'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '45 320');
    await tester.tap(find.text('Mentés'));
    await tester.pumpAndSettle();
    expect(terms?.threshold, 113.3);
  });
}
