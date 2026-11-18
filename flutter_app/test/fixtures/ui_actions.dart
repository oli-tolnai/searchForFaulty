import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> openHidden(WidgetTester tester, String label, {int? count}) async {
  final scrolling = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  final footer = find.textContaining('Rejtett tételek (');
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
