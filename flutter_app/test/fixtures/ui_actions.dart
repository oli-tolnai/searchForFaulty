import 'package:flutter_app/listing_card.dart';
import 'package:flutter_app/search_filter_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> openHidden(WidgetTester tester, String label, {int? count}) async {
  final scrolling = find
      .descendant(
        of: find.byKey(const PageStorageKey('all-null')).evaluate().isNotEmpty
            ? find.byKey(const PageStorageKey('all-null'))
            : find.byWidgetPredicate(
                (w) =>
                    w is ListView &&
                    w.key is PageStorageKey &&
                    (w.key as PageStorageKey).value.toString().endsWith(
                      '-null',
                    ),
              ),
        matching: find.byType(Scrollable),
      )
      .first;
  final footer = find.textContaining('Rejtett tételek (').last;
  await tester.scrollUntilVisible(footer, 300, scrollable: scrolling);
  final row = find.widgetWithText(ListTile, label);
  if (row.evaluate().isEmpty) {
    await tester.tap(footer);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  for (var i = 0; i < 10 && row.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  expect(row.hitTestable(), findsOneWidget);
  if (count != null) {
    expect(
      find.descendant(of: row, matching: find.text('$count')),
      findsOneWidget,
    );
  }
  await tester.tap(row.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> selectCategory(WidgetTester tester, String label) async {
  final desktop = find.widgetWithText(ChoiceChip, label);
  if (desktop.evaluate().isNotEmpty) {
    await tester.ensureVisible(desktop);
    await tester.tap(desktop);
  } else {
    await tester.tap(find.byKey(const ValueKey('category-picker')));
    await tester.pumpAndSettle();
    const groups = {
      'Összes': 'all',
      'Konzol': 'consoles',
      'Kontroller': 'controllers',
      'Switch': 'switch',
      'Steam Deck': 'steam_deck',
      'iPhone': 'iphone',
      'Videokártya': 'gpu',
    };
    final row = find.byKey(ValueKey('category-${groups[label]}'));
    await tester.ensureVisible(row);
    await tester.tap(row);
  }
  await tester.pumpAndSettle();
}

Future<void> openListing(WidgetTester tester, {String? title}) async {
  final currentTitle =
      title ??
      tester.widget<ListingCard>(find.byType(ListingCard).first).item.title;
  final card = find.text(currentTitle).first;
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Future<void> description(WidgetTester tester) async {
  final row = find.text('Leírás és az eladó megjegyzése');
  final scroll = find
      .descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is ListView &&
              w.key is PageStorageKey &&
              (w.key as PageStorageKey).value.toString().startsWith('detail-'),
        ),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(row, 250, scrollable: scroll);
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> openFilters(WidgetTester tester) async {
  if (find
      .byWidgetPredicate((w) => w is SearchFilterPanel && w.desktop)
      .evaluate()
      .isNotEmpty) {
    return;
  }
  final button = find.textContaining('Szűrők').hitTestable().first;
  await tester.tap(button);
  await tester.pumpAndSettle();
}
