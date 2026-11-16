import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_app/settings_screen.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_app/watch_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/responses.dart';

void main() {
  SharedState offline() => SharedState(
    readRemote: (_) async => throw const AppFailure('offline'),
    writeRemote: (_) async => throw const AppFailure('offline'),
    refreshRemote: () async => {},
    save: (_) async {},
    clock: () => testTime,
  );

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(1150, 1440));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: page));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('auction card adds a watch and the tab edits and deletes it', (
    tester,
  ) async {
    final shared = offline();
    addTearDown(shared.dispose);
    final result = SearchResult.fromJson(
      search(
        unknown: [
          listing(
            title: 'Figyelt aukció',
            end: testTime.add(const Duration(hours: 3)),
          ),
        ],
      ),
    );
    await show(
      tester,
      SearchScreen(
        initial: result,
        clock: () => testTime,
        shared: shared,
        search: () async => result,
        loadDetails: (_) async => ListingDetails.fromJson(details),
      ),
    );
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -550),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(OutlinedButton, 'Figyelés'));
    expect(find.text('Aukció figyelése'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '101,50');
    await tap(tester, find.text('Mentés'));

    expect(shared.watches.single.threshold, 101.5);
    expect(shared.watches.single.lead, 120);
    expect(find.text('Figyelve · 101.5 €'), findsOneWidget);
    await tap(tester, find.widgetWithText(NavigationDestination, 'Figyelés'));
    expect(find.text('Aktív'), findsOneWidget);
    await tap(tester, find.byTooltip('Figyelés szerkesztése'));
    await tester.enterText(find.byType(TextFormField), '120');
    await tap(tester, find.text('2 órával előtte'));
    await tap(tester, find.text('30 perccel előtte').last);
    await tap(tester, find.text('Mentés'));
    expect(shared.watches.single.threshold, 120);
    expect(shared.watches.single.lead, 30);

    await tap(tester, find.byTooltip('Figyelés törlése'));
    expect(shared.watches, isEmpty);
    expect(find.text('Még nincsenek figyelt aukciók.'), findsOneWidget);
  });

  testWidgets('new-listing rules can be added, edited, disabled and deleted', (
    tester,
  ) async {
    final shared = offline();
    addTearDown(shared.dispose);
    await show(
      tester,
      ListenableBuilder(
        listenable: shared,
        builder: (context, child) => WatchScreen(shared: shared, now: testTime),
      ),
    );
    await tap(tester, find.text('Új szabály'));
    await tap(tester, find.text('PS5 Slim'));
    await tester.enterText(find.byType(TextFormField), '160');
    await tap(tester, find.text('Ismeretlen szállítás bevonása'));
    await tap(tester, find.text('Mentés'));
    expect(shared.alerts.single.models, ['PS5 Slim']);
    expect(shared.alerts.single.includeUnknown, true);
    expect(shared.alerts.single.maxTotal, 160);
    expect(shared.alerts.single.enabled, true);

    await tap(tester, find.byTooltip('Szabály szerkesztése'));
    await tap(tester, find.text('Szabály engedélyezve'));
    await tap(tester, find.text('Mentés'));
    expect(shared.alerts.single.enabled, false);
    expect(find.textContaining('Kikapcsolva'), findsOneWidget);
    await tap(tester, find.byTooltip('Szabály törlése'));
    expect(shared.alerts, isEmpty);
  });

  testWidgets('settings sends a test notification and shows feedback', (
    tester,
  ) async {
    var requests = 0;
    const endpoint = 'https://script.google.com/macros/s/test/exec';
    await show(
      tester,
      SettingsScreen(
        initial: WebappSettings(endpoint, 'fixture-token'),
        save: (_) async =>
            fail('Sending a notification must not save settings.'),
        sendTestNotification: (settings) async {
          expect(settings.endpoint.toString(), endpoint);
          requests++;
        },
      ),
    );
    await tap(tester, find.text('Próbaértesítés küldése'));
    expect(requests, 1);
    expect(find.text('A próbaértesítést elküldtük.'), findsOneWidget);
  });
}
