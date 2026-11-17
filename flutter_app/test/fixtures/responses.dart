import 'package:flutter_app/api/models.dart';

final testTime = DateTime.utc(2026, 11, 15, 12);

Json queuedAuction(DateTime now) => {
  'id': '2fd77dea-3f65-4dea-a6f2-5c403173d27c',
  'created_at': now.toUtc().toIso8601String(),
  'kind': 'auction_closing',
  'title': 'Aukció zárul',
  'body': 'Ma 19:30-kor zárul: PS5 Slim – 120 €',
  'url': 'https://www.ebay.de/itm/123',
  'source_listing_ids': ['v1|123|0'],
  'expires_at': now.toUtc().add(const Duration(hours: 1)).toIso8601String(),
};

Json listing({
  String id = 'v1|123|0',
  String title = 'Tesztkonzol',
  String? shipping,
  String? total,
  DateTime? end,
  DateTime? listedAt,
  DateTime? checkedAt,
  String price = '75',
  String type = 'console',
  String model = 'PS5 Slim',
  String deviceGroup = 'consoles',
  bool isScuf = false,
  String shipsToHu = 'yes',
  bool isNew = false,
}) => {
  'source': 'ebay',
  'source_listing_id': id,
  'title': title,
  'url': 'https://example.test/item',
  'image_url': null,
  'console_model': model,
  'item_type': type,
  'device_group': deviceGroup,
  'is_scuf': isScuf,
  'is_banned': false,
  'possibly_not_faulty': false,
  'buying_options': [end == null ? 'FIXED_PRICE' : 'AUCTION'],
  'price': end == null ? price : null,
  'current_bid': end == null ? null : price,
  'bid_count': end == null ? null : 2,
  'currency': 'EUR',
  'shipping_cost': shipping,
  'ships_to_hu': shipsToHu,
  'is_new': isNew,
  'shipping_currency': shipping == null ? null : 'EUR',
  'total_price': total,
  'item_country': 'DE',
  'end_time': end?.toIso8601String(),
  'listed_at': listedAt?.toIso8601String(),
  'condition': null,
  'status': 'ACTIVE',
  'last_checked_at': (checkedAt ?? testTime).toIso8601String(),
  'fault_source': 'condition',
};

Json search({
  String status = 'success',
  List<Json> known = const [],
  List<Json> unknown = const [],
  List<Json> countries = const [],
}) => {
  'status': status,
  'listings': known,
  'unknown_shipping': unknown,
  'countries': countries,
  'item_type_counts': {for (final type in itemTypes) type: 0},
  'unknown_shipping_breakdown': {
    'by_buying_type': {'auction': 0, 'fixed_price': 0},
    'by_country': <String, Object?>{},
  },
  'filtered_non_eu': 0,
  'api_calls': 55,
  'get_item_calls': 0,
  'shipping_check': {
    'initial_unknown': 0,
    'yes': 0,
    'no': 0,
    'unknown': 0,
    'failed': 0,
  },
  'daily_api_calls': 55,
  'daily_browse_calls': 54,
  'quota_warning': null,
  'searched_at': testTime.toIso8601String(),
};

const details = {
  'condition_description': 'Defektes Laufwerk',
  'description_text': 'Originalverpackt mit Zubehör',
  'short_description': null,
};
