// Manual UI rendering from an actual, fresh local search cache. No sample listings.
// Run with: flutter test tools/capture_ui.dart --dart-define=CDF_CAPTURE_FILE=...
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/api/webapp.dart';
import 'package:flutter_app/app_theme.dart';
import 'package:flutter_app/group_results.dart';
import 'package:flutter_app/listing_card.dart';
import 'package:flutter_app/search_screen.dart';
import 'package:flutter_app/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class ImageHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionTimeout = const Duration(seconds: 15);
}

void main() {
  testWidgets('render approved UI states using actual cached listings', (
    tester,
  ) async {
    const path = String.fromEnvironment('CDF_CAPTURE_FILE');
    if (path.isEmpty) {
      throw StateError(
        'CDF_CAPTURE_FILE szükséges: friss, valódi keresési gyorsítótár.',
      );
    }
    final raw = object(jsonDecode(File(path).readAsStringSync()));
    final groups = GroupResults.fromJson(raw)..expire(DateTime.now());
    if (groups.all(deviceGroups).isEmpty) {
      throw StateError(
        'A gyorsítótárban nincs hat órán belüli hirdetés. Előbb keress az appban.',
      );
    }
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final output = Directory('../docs/ui_terv/kepernyokepek')
      ..createSync(recursive: true);
    final root = GlobalKey();
    var generation = 0;
    late SharedState shared;
    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(() async {
        final boundary =
            root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${output.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> mount(
      Size size, {
      DateTime? clock,
      Completer<SearchResult>? pending,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      shared = SharedState(
        readRemote: (_) async => throw const AppFailure('offline'),
        writeRemote: (_) async => throw const AppFailure('offline'),
        refreshRemote: () async => {},
        save: (_) async {},
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: root,
          child: MaterialApp(
            theme: Ui.theme,
            debugShowCheckedModeBanner: false,
            locale: const Locale('hu'),
            supportedLocales: const [Locale('hu')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: SearchScreen(
              key: ValueKey(generation++),
              initialGroups: GroupResults.fromJson(raw)
                ..expire(clock ?? DateTime.now()),
              shared: shared,
              clock: () => clock ?? DateTime.now(),
              search: (_) =>
                  pending?.future ??
                  Future.error(
                    StateError('Új keresést a natív alkalmazásból indíts.'),
                  ),
              loadDetails: (_) async => throw StateError(
                'Részletlekérés a natív alkalmazásban érhető el.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final imageUrls = groups
          .all(deviceGroups)
          .map((i) => i.image)
          .whereType<Uri>()
          .where((u) => u.host.endsWith('.ebayimg.com'))
          .take(40)
          .toSet();
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final context = root.currentContext!;
          await Future.wait(
            imageUrls.map(
              (uri) => precacheImage(
                NetworkImage(uri.toString()),
                context,
                onError: (_, _) {},
              ),
            ),
          );
        }, ImageHttp()),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> category(String group) async {
      final chip = find.widgetWithText(
        ChoiceChip,
        group == 'consoles'
            ? 'Konzol'
            : group == 'steam_deck'
            ? 'Steam Deck'
            : group,
      );
      if (chip.evaluate().isNotEmpty) {
        await tester.tap(chip);
      } else {
        await tester.tap(find.byKey(const ValueKey('category-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('category-$group')));
      }
      await tester.pumpAndSettle();
    }

    late BuildContext warmContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            warmContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.runAsync(
      () => HttpOverrides.runWithHttpOverrides(() async {
        await Future.wait(
          groups
              .all(deviceGroups)
              .map((i) => i.image)
              .whereType<Uri>()
              .where((u) => u.host.endsWith('.ebayimg.com'))
              .take(40)
              .toSet()
              .map(
                (u) => precacheImage(
                  NetworkImage(u.toString()),
                  warmContext,
                  onError: (_, _) {},
                ),
              ),
        );
      }, ImageHttp()),
    );
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      final suffix = '${size.width.toInt()}x${size.height.toInt()}';
      final pending = Completer<SearchResult>();
      await mount(size, pending: pending);
      await category('consoles');
      await capture('Main_$suffix');
      if (size.width < 1000) {
        await tester.tap(find.byKey(const ValueKey('category-picker')));
        await tester.pumpAndSettle();
        await capture('Kategoria_$suffix');
        await tester.tap(find.byKey(const ValueKey('category-consoles')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Szűrők').hitTestable().first);
        await tester.pumpAndSettle();
        await capture('Szurok_$suffix');
        await tester.tap(find.byTooltip('Szűrők bezárása'));
        await tester.pumpAndSettle();
      } else {
        await capture('Asztali_$suffix');
        await capture('Szurok_$suffix');
      }
      final card = find
          .byWidgetPredicate(
            (w) =>
                w is ListingCard &&
                w.item.auction &&
                w.item.model.contains('Slim'),
          )
          .first;
      final title = tester.widget<ListingCard>(card).item.title;
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
      await capture('Reszletek_$suffix');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-search')));
      await tester.pump(const Duration(milliseconds: 400));
      await capture('Betoltes_$suffix');
      await tester.tap(find.text('Mégse'));
      pending.complete(groups.groups['consoles']!);
      await tester.pumpAndSettle();
      await category('steam_deck');
      await capture('Ures_$suffix');
      await tester.pumpWidget(const SizedBox());
      shared.dispose();
      // The clock advances only in this diagnostic render, never in production.
      // Actual listing prices/titles remain unchanged; the caption documents the simulated age.
      final searched = groups.groups['consoles']!.searchedAt;
      await mount(size, clock: searched.add(const Duration(hours: 3)));
      await category('consoles');
      final list = find.byWidgetPredicate(
        (w) => w is ListView && w.key == const PageStorageKey('consoles-null'),
      );
      final scrolling = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      // Keep the stale banner in the image; hidden groups remain independently accessible at the bottom.
      await capture('Elavult_$suffix');
      final hidden = find.byKey(const PageStorageKey('hidden-footer-consoles'));
      await tester.scrollUntilVisible(hidden, 500, scrollable: scrolling);
      final hiddenTitle = find.descendant(
        of: hidden,
        matching: find.textContaining('Rejtett tételek ('),
      );
      await tester.ensureVisible(hiddenTitle);
      if (find
          .widgetWithText(ListTile, 'Nem támogatott modell')
          .evaluate()
          .isEmpty) {
        await tester.tap(hiddenTitle);
      }
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      await capture('Rejtett_$suffix');
      await tester.pumpWidget(const SizedBox());
      shared.dispose();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
