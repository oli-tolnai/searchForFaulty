import 'package:intl/intl.dart';

import 'api/models.dart';

const day = Duration(days: 1);
const uncheckedAfter = Duration(hours: 2);
const maxListingAge = Duration(hours: 6);

enum HiddenGroup {
  unsupported('Nem támogatott modell', 'unsupported_model'),
  accessory('Nem konzol', 'not_console'),
  mainboard('Alaplap', 'mainboard'),
  noShipping('Nem szállít Magyarországra', null);

  const HiddenGroup(this.title, this.type);
  final String title;
  final String? type;

  bool contains(Listing item) =>
      type == null ? item.shipsToHu == 'no' : item.type == type;
}

bool inMainResults(Listing item, {required bool mainboards}) =>
    item.shipsToHu != 'no' &&
    !HiddenGroup.unsupported.contains(item) &&
    !HiddenGroup.accessory.contains(item) &&
    (mainboards || !HiddenGroup.mainboard.contains(item));

bool inUnknownShippingBlock(Listing item) =>
    item.shipping == null || item.shipsToHu == 'unknown';

const consoleModels = [
  'PS5 (Fat)',
  'PS5 Slim',
  'PS5 Pro',
  'PS5 (változat nem ismert)',
  'Xbox Series X',
  'Xbox Series S',
];

const countries = {
  'AT': 'Ausztria',
  'BE': 'Belgium',
  'BG': 'Bulgária',
  'HR': 'Horvátország',
  'CY': 'Ciprus',
  'CZ': 'Csehország',
  'DK': 'Dánia',
  'EE': 'Észtország',
  'FI': 'Finnország',
  'FR': 'Franciaország',
  'DE': 'Németország',
  'GR': 'Görögország',
  'HU': 'Magyarország',
  'IE': 'Írország',
  'IT': 'Olaszország',
  'LV': 'Lettország',
  'LT': 'Litvánia',
  'LU': 'Luxemburg',
  'MT': 'Málta',
  'NL': 'Hollandia',
  'PL': 'Lengyelország',
  'PT': 'Portugália',
  'RO': 'Románia',
  'SK': 'Szlovákia',
  'SI': 'Szlovénia',
  'ES': 'Spanyolország',
  'SE': 'Svédország',
};

String countryName(String? code) => countries[code] ?? code ?? 'Nem ismert';
final _dateFormat = DateFormat('yyyy. MM. dd. HH:mm');
String dateLabel(DateTime time) => _dateFormat.format(time.toLocal());

String money(String? value, String? currency) {
  if (value == null || currency == null) return 'Nem ismert';
  return NumberFormat.currency(
    locale: 'hu',
    name: currency,
    symbol: currency,
  ).format(double.parse(value));
}

String countdown(Duration remaining) {
  final seconds = (remaining.inMilliseconds / 1000).ceil().clamp(0, 1 << 32);
  final days = seconds ~/ 86400;
  final hours = seconds ~/ 3600 % 24;
  final minutes = seconds ~/ 60 % 60;
  if (days > 0) return '$days nap $hours óra';
  if (hours > 0) return '$hours óra $minutes perc';
  return '$minutes perc ${seconds % 60} mp';
}

enum BuyingFilter {
  both('Mind'),
  auction('Aukció'),
  fixed('Fix ár');

  const BuyingFilter(this.label);
  final String label;
}

enum ListingOrder {
  total('Legalacsonyabb ismert teljes ár'),
  cheap('Legolcsóbb'),
  expensive('Legdrágább'),
  newest('Legújabb'),
  ending('Leghamarabb záródó');

  const ListingOrder(this.label);
  final String label;
}

class ListingFilters {
  const ListingFilters({
    this.models = const {},
    this.maxPrice,
    this.maxTotal,
    this.buying = BuyingFilter.both,
    this.endingSoon = false,
    this.mainboards = false,
    this.title = '',
    this.country,
  });
  final Set<String> models;
  final double? maxPrice, maxTotal;
  final BuyingFilter buying;
  final bool endingSoon, mainboards;
  final String title;
  final String? country;

  bool matches(Listing item, DateTime now) {
    if (!inMainResults(item, mainboards: mainboards)) return false;
    if (buying == BuyingFilter.auction && !item.auction) return false;
    if (buying == BuyingFilter.fixed && !item.options.contains('FIXED_PRICE')) {
      return false;
    }
    if (endingSoon && item.auction && item.end!.difference(now) > day) {
      return false;
    }
    final family = item.model == 'PS5 Digital'
        ? 'PS5 (változat nem ismert)'
        : item.model.replaceFirst(RegExp(r' (Disc|Digital)$'), '');
    if (models.isNotEmpty &&
        !models.contains(item.model) &&
        !models.contains(family)) {
      return false;
    }
    if (country != null && item.country != country) return false;
    if (!item.title.toLowerCase().contains(title.trim().toLowerCase())) {
      return false;
    }
    if (maxPrice != null &&
        (item.effectivePrice == null ||
            double.parse(item.effectivePrice!) > maxPrice!)) {
      return false;
    }
    if (maxTotal != null &&
        item.shipping != null &&
        (item.total == null || double.parse(item.total!) > maxTotal!)) {
      return false;
    }
    return true;
  }
}

bool visibleListing(Listing item, DateTime now) =>
    item.status == 'ACTIVE' &&
    now.difference(item.checkedAt) < maxListingAge &&
    (!item.auction || item.end?.isAfter(now) == true);

bool isUnchecked(Listing item, DateTime now) =>
    now.difference(item.checkedAt) >= uncheckedAfter;

int _compare<T extends Comparable<T>>(T? a, T? b, {bool descending = false}) {
  if (a == null) return b == null ? 0 : 1;
  if (b == null) return -1;
  return descending ? b.compareTo(a) : a.compareTo(b);
}

num? _price(String? amount) => amount == null ? null : num.parse(amount);

List<Listing> selectListings(
  Iterable<Listing> items,
  ListingFilters filters,
  ListingOrder order,
  DateTime now,
) {
  final selected = items
      .where((item) => visibleListing(item, now) && filters.matches(item, now))
      .toList();
  selected.sort((a, b) {
    if (inUnknownShippingBlock(a) != inUnknownShippingBlock(b)) {
      return inUnknownShippingBlock(a) ? 1 : -1;
    }
    final comparison = switch (order) {
      ListingOrder.total => _compare(_price(a.total), _price(b.total)),
      ListingOrder.cheap => _compare(
        _price(a.effectivePrice),
        _price(b.effectivePrice),
      ),
      ListingOrder.expensive => _compare(
        _price(a.effectivePrice),
        _price(b.effectivePrice),
        descending: true,
      ),
      ListingOrder.newest => _compare(a.listedAt, b.listedAt, descending: true),
      ListingOrder.ending => _compare(
        a.auction ? a.end : null,
        b.auction ? b.end : null,
      ),
    };
    return comparison != 0 ? comparison : a.id.compareTo(b.id);
  });
  return selected;
}
