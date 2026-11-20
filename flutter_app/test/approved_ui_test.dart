import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/app_theme.dart';
import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_app/listing_card.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_app/search_filter_panel.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/responses.dart';
import 'fixtures/ui_actions.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
  });
  SharedState state() => SharedState(
    readRemote: (_) async => throw const AppFailure('offline'),
    writeRemote: (_) async => throw const AppFailure('offline'),
    refreshRemote: () async => {},
    save: (_) async {},
  );
  Future<void> size(WidgetTester t, double width, double height) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Widget page(
    SharedState s, {
    Future<SearchResult> Function(Set<String>)? request,
  }) => MaterialApp(
    theme: Ui.theme,
    home: SearchScreen(
      shared: s,
      clock: () => testTime,
      initial: SearchResult.fromJson(
        search(
          known: [
            listing(
              title: 'Olcsó konzol',
              price: '30',
              shipping: '5',
              total: '35',
            ),
            listing(
              id: 'two',
              title: 'Drága konzol',
              price: '100',
              shipping: '5',
              total: '105',
            ),
          ],
        ),
      ),
      search: request ?? (_) async => SearchResult.fromJson(search()),
      loadDetails: (_) async => ListingDetails.fromJson(details),
    ),
  );
  testWidgets(
    'phone has four destinations, category picker and live filter result count',
    (t) async {
      await size(t, 390, 844);
      final s = state();
      addTearDown(s.dispose);
      await t.pumpWidget(page(s));
      await t.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.byType(ChoiceChip), findsNothing);
      await t.tap(find.byKey(const ValueKey('category-picker')));
      await t.pumpAndSettle();
      expect(find.text('Mit keresel?'), findsOneWidget);
      expect(find.byKey(const ValueKey('category-all')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('category-consoles')));
      await t.pumpAndSettle();
      await openFilters(t);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('2 találat mutatása'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Ár eddig (EUR)'),
        '50',
      );
      await t.pumpAndSettle();
      expect(find.text('1 találat mutatása'), findsOneWidget);
      expect(find.text('A cím tartalmazza bármelyiket'), findsNothing);
      await t.tap(find.text('1 találat mutatása'));
      await t.pumpAndSettle();
      expect(find.text('Olcsó konzol'), findsOneWidget);
      expect(find.text('Drága konzol'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'compact card opens full phone details and only description fetches data',
    (t) async {
      await size(t, 390, 844);
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: Ui.theme,
          home: Scaffold(
            body: ListingCard(
              item: Listing.fromJson({
                ...listing(title: 'Részletes hirdetés'),
                'is_banned': true,
              }),
              now: testTime,
              loadDetails: (_) async {
                calls++;
                return ListingDetails.fromJson(details);
              },
              onUnavailable: () {},
              onFavorite: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Megnyitás az eBay-en'), findsNothing);
      expect(find.text('Tiltott (banned)'), findsNothing);
      await openListing(t, title: 'Részletes hirdetés');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Tiltott (banned)'), findsOneWidget);
      expect(calls, 0);
      await description(t);
      expect(calls, 1);
      expect(find.text('Google Fordító megnyitása'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'desktop keeps a 272 pixel panel, four columns and dialog details',
    (t) async {
      await size(t, 1440, 900);
      final s = state();
      addTearDown(s.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: Ui.theme,
          home: SearchScreen(
            shared: s,
            clock: () => testTime,
            initial: SearchResult.fromJson(
              search(
                known: [
                  for (var i = 0; i < 4; i++)
                    listing(
                      id: 'card-$i',
                      title: 'Konzol $i',
                      price: '50',
                      shipping: '5',
                      total: '55',
                    ),
                ],
              ),
            ),
            search: (_) async => SearchResult.fromJson(search()),
            loadDetails: (_) async => ListingDetails.fromJson(details),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(t.getSize(find.byType(SearchFilterPanel)).width, 272);
      final y = [
        for (var i = 0; i < 4; i++) t.getTopLeft(find.text('Konzol $i')).dy,
      ];
      expect(y.toSet().length, 1);
      await openListing(t, title: 'Konzol 0');
      expect(find.byType(Dialog), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel keeps previous listings and ignores the eventual response',
    (t) async {
      await size(t, 390, 844);
      final s = state();
      addTearDown(s.dispose);
      final pending = Completer<SearchResult>();
      await t.pumpWidget(page(s, request: (_) => pending.future));
      await t.pumpAndSettle();
      await selectCategory(t, 'Konzol');
      await t.tap(find.byKey(const ValueKey('run-search')));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Keresés folyamatban…'), findsOneWidget);
      expect(find.text('Olcsó konzol'), findsOneWidget);
      await t.tap(find.text('Mégse'));
      await t.pump();
      pending.complete(SearchResult.fromJson(search()));
      await t.pumpAndSettle();
      expect(find.text('Olcsó konzol'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
