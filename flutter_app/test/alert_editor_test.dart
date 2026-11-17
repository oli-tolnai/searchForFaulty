import 'package:flutter_app/alert_editor.dart';
import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/currency.dart';
import 'package:flutter_app/notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('old alert rules acquire the new defaults', () {
    final rule = AlertRule({
      'id': 'legacy-rule-test',
      'models': ['DualSense'],
      'max_total_price': 100,
      'include_unknown_shipping': true,
      'enabled': true,
    });
    expect(rule.groups, ['controllers']);
    expect(rule.includeUnknown, true);
    expect(rule.excludePossiblyNotFaulty, true);
    expect(rule.excludeBanned, false);
    expect(rule.includeTitleFaults, true);
    expect(rule.buying, 'both');
    expect(rule.endingHours, null);
    expect(rule.includeKeywords, isEmpty);
    expect(rule.maxPrice, null);
    expect(rule.name, 'Értesítési szabály');
  });

  testWidgets(
    'expanded alert editor saves filters and converts HUF amounts to EUR',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Json? saved;
      final quote = ExchangeRate.fromJson({
        'eur_huf': 400,
        'date': '2026-11-17',
        'source': 'ECB',
        'stale': false,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MoneyScope(
            display: MoneyDisplay('HUF', quote),
            toggle: null,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await editAlert(context, null);
                  },
                  child: const Text('Szabály'),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.text('Szabály'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Név'),
        'Driftes kontrollerek',
      );
      await tap(find.text('Konzolok'));
      await tap(find.text('DualSense'));
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Max. vételár vagy aktuális licit (Ft)',
        ),
        '40 000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Max. teljes ár (Ft)'),
        '44 000',
      );
      await tap(find.text('Mind'));
      await tap(find.text('Csak aukció').last);
      await tap(find.text('Nincs időkorlát'));
      await tap(find.text('12 órán belül').last);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'A cím tartalmazza bármelyiket'),
        'Drift, Stick',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'A cím egyiket se tartalmazza'),
        'banned',
      );
      await tap(find.text('Tiltott (banned) tételek kizárása'));
      await tap(
        find.text('Használtként hirdetett, cím szerint hibás tételek bevonása'),
      );
      await tap(find.text('Mentés'));
      expect(saved?['name'], 'Driftes kontrollerek');
      expect(saved?['device_groups'], ['controllers']);
      expect(saved?['models'], ['DualSense']);
      expect(saved?['max_price'], 100);
      expect(saved?['max_total_price'], 110);
      expect(saved?['ending_hours'], 12);
      expect(saved?['buying_options'], 'auction');
      expect(saved?['include_keywords'], ['Drift', 'Stick']);
      expect(saved?['exclude_keywords'], ['banned']);
      expect(saved?['exclude_banned'], true);
      expect(saved?['include_title_faults'], false);
    },
  );
}
