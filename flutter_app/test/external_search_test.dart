import 'package:flutter/services.dart';
import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_app/app_theme.dart';
import 'package:flutter_app/external_search.dart';
import 'package:flutter_app/search_filters.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures/responses.dart';
import 'fixtures/ui_actions.dart';

void main() {
  test('fallback estimates count distinct groups and all 27 countries', () {
    expect(estimatedBaseCalls(['consoles']), 56);
    expect(estimatedBaseCalls(['controllers']), 112);
    expect(estimatedBaseCalls(['switch']), 27);
    expect(estimatedBaseCalls(['steam_deck']), 27);
    expect(estimatedBaseCalls(['iphone']), 189);
    expect(estimatedBaseCalls(['gpu']), 54);
    expect(estimatedBaseCalls(['consoles', 'controllers', 'consoles']), 168);
    expect(estimatedBaseCalls(['unexpected']), isNull);
  });
  test('external queries use first selected model or category fallback', () {
    expect(externalSearchText('consoles', []), 'ps5 hibás');
    expect(externalSearchText('controllers', []), 'dualsense hibás');
    expect(externalSearchText('switch', []), 'nintendo switch hibás');
    expect(externalSearchText('steam_deck', []), 'steam deck hibás');
    expect(externalSearchText('iphone', []), 'iphone hibás');
    expect(externalSearchText('gpu', []), 'videókártya hibás');
    expect(
      externalSearchText('consoles', ['Xbox Series X', 'PS5 Slim']),
      'Xbox Series X hibás',
    );
    expect(externalSearchText('switch', ['Switch OLED']), 'Switch OLED hibás');
  });
  test('search URL encoding preserves accents and special characters', () {
    const text = 'videókártya & PS5 + hibás';
    for (final site in ExternalMarket.values) {
      final uri = externalSearchUri(site, text);
      expect(uri.scheme, 'https');
      expect(uri.queryParameters, {site.parameter: text});
      expect(uri.toString(), contains('%C3%B3'));
    }
    expect(
      externalSearchUri(ExternalMarket.jofogas, text).path,
      '/magyarorszag',
    );
    expect(
      externalSearchUri(ExternalMarket.hardverapro, text).path,
      '/aprok/keres.php',
    );
  });
  testWidgets(
    'empty phone category has both links and launches outside the app',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        launched.add(call.arguments['url'] as String);
        return true;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final s = SharedState(
        readRemote: (_) async => throw const AppFailure('offline'),
        writeRemote: (_) async => throw const AppFailure('offline'),
        refreshRemote: () async => {},
        save: (_) async {},
      );
      addTearDown(s.dispose);
      await s.setSearchFilter(
        'controllers',
        GroupSearchFilter({
          'models': ['DualSense Edge', 'DualSense'],
        }),
      );
      var searches = 0;
      const windowsChannel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.url_launcher_windows.UrlLauncherApi.launchUrl',
        StandardMessageCodec(),
      );
      t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        windowsChannel,
        (message) async {
          launched.add((message as List).first as String);
          return [true];
        },
      );
      addTearDown(() {
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
          windowsChannel,
          null,
        );
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Ui.theme,
          home: SearchScreen(
            shared: s,
            clock: () => testTime,
            search: (_) async {
              searches++;
              return SearchResult.fromJson(search());
            },
            loadDetails: (_) async => ListingDetails.fromJson(details),
          ),
        ),
      );
      await t.pumpAndSettle();
      await selectCategory(t, 'Kontroller');
      final list = find.byType(ListView).first;
      await t.scrollUntilVisible(
        find.text('Jófogás'),
        250,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Keress máshol is'), findsOneWidget);
      expect(find.text('HardverApró'), findsOneWidget);
      expect(find.text('DualSense Edge hibás'), findsOneWidget);
      await t.drag(list, const Offset(0, -300));
      await t.pumpAndSettle();
      expect(find.text('Jófogás').hitTestable(), findsOneWidget);
      await t.tap(find.text('Jófogás').hitTestable());
      await t.pumpAndSettle();
      expect(launched, hasLength(1));
      expect(
        Uri.parse(launched.single).queryParameters['q'],
        'DualSense Edge hibás',
      );

      expect(searches, 0);
    },
  );
  testWidgets(
    'desktop uses local call estimate without permanent cached-result label',
    (t) async {
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          theme: Ui.theme,
          home: SearchScreen(
            initial: SearchResult.fromJson(
              search(known: [listing(title: 'Mentett konzol')]),
            ),
            clock: () => testTime,
            search: (_) async => SearchResult.fromJson(search()),
            loadDetails: (_) async => ListingDetails.fromJson(details),
          ),
        ),
      );
      await t.pumpAndSettle();
      await selectCategory(t, 'Konzol');
      expect(find.text('Keresés · kb. 56 hívás'), findsOneWidget);
      expect(find.textContaining('becslés nincs'), findsNothing);
      expect(find.textContaining('Korábban mentett eredmény'), findsNothing);
      expect(find.textContaining('Offline –'), findsNothing);
      expect(find.text('Legolcsóbb teljes ár'), findsOneWidget);
      final panel = find.byType(ListView).first;
      await t.scrollUntilVisible(
        find.text('HardverApró'),
        300,
        scrollable: find
            .descendant(of: panel, matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Keress máshol is'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
