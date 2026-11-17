import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'api/models.dart';

class MoneyDisplay {
  const MoneyDisplay(this.preference, this.rate);
  final String preference;
  final ExchangeRate? rate;

  bool get huf => preference == 'HUF' && rate != null;
  String get unit => huf ? 'Ft' : 'EUR';

  String format(String? raw, String? source) {
    final amount = raw == null ? null : double.tryParse(raw);
    if (amount == null || !amount.isFinite) return 'Nem ismert';
    if (source == 'EUR') {
      final converted = huf ? amount * rate!.eurHuf : amount;
      if (!converted.isFinite) return 'Nem ismert';
      return huf ? '${grouped(converted, 0)} Ft' : '${grouped(converted, 2)} €';
    }
    if (source == 'HUF') {
      if (huf) return '${grouped(amount, 0)} Ft';
      if (rate != null) return '${grouped(amount / rate!.eurHuf, 2)} €';
    }
    return 'Nem ismert';
  }

  String euroInput(num? value) {
    if (value == null) return '';
    final converted = huf ? value * rate!.eurHuf : value;
    return converted.isFinite ? grouped(converted, huf ? 0 : 2) : '';
  }

  double? inputToEuro(String? text) {
    final input =
        text?.replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.') ?? '';
    final amount = double.tryParse(input);
    if (amount == null ||
        !amount.isFinite ||
        amount < 0 ||
        (huf && amount != amount.roundToDouble())) {
      return null;
    }
    final euro = huf ? amount / rate!.eurHuf : amount;
    return euro.isFinite ? euro : null;
  }

  String get rateLabel {
    final quote = rate;
    if (quote == null) return 'Az ECB árfolyama jelenleg nem ismert.';
    final date = DateFormat('yyyy. MM. dd.').format(quote.date);
    return '1 EUR = ${grouped(quote.eurHuf, 2)} Ft (ECB, $date)${quote.stale ? ' · korábbi árfolyam' : ''}';
  }

  static String grouped(num value, int fractionDigits) {
    final format = NumberFormat.decimalPattern('hu')
      ..maximumFractionDigits = fractionDigits;
    return format
        .format(value)
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u202f', ' ');
  }
}

class MoneyScope extends InheritedWidget {
  const MoneyScope({
    super.key,
    required this.display,
    required this.toggle,
    required super.child,
  });
  final MoneyDisplay display;
  final VoidCallback? toggle;

  static MoneyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoneyScope>();

  static MoneyDisplay displayOf(BuildContext context) =>
      maybeOf(context)?.display ?? const MoneyDisplay('EUR', null);

  @override
  bool updateShouldNotify(MoneyScope oldWidget) =>
      oldWidget.display.preference != display.preference ||
      oldWidget.display.rate != display.rate ||
      (oldWidget.toggle == null) != (toggle == null);
}

class PriceText extends StatelessWidget {
  const PriceText(
    this.amount,
    this.source, {
    super.key,
    this.prefix = '',
    this.style,
    this.textAlign,
  });
  final String? amount, source;
  final String prefix;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final scope = MoneyScope.maybeOf(context);
    final display = scope?.display ?? const MoneyDisplay('EUR', null);
    final value = display.format(amount, source);
    final text = Text(prefix + value, style: style, textAlign: textAlign);
    if (value == 'Nem ismert' || scope?.toggle == null || display.rate == null) {
      return text;
    }
    return Tooltip(
      message: display.huf ? 'Váltás euróra' : 'Váltás forintra',
      child: InkWell(onTap: scope!.toggle, child: text),
    );
  }
}
