typedef Json = Map<String, Object?>;

final notificationUuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);

Uri? notificationListingLink(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  final host = RegExp(
    r'^(?:[a-z0-9-]+\.)*ebay\.(?:de|com|fr|it|es|nl|at|ie|be|co\.uk)$',
  );
  return uri != null &&
          uri.scheme == 'https' &&
          uri.userInfo.isEmpty &&
          uri.port == 443 &&
          host.hasMatch(uri.host)
      ? uri
      : null;
}

class QueuedNotification {
  QueuedNotification.fromJson(Object? value) : this._(Fields(value));

  QueuedNotification._(Fields fields)
    : id = fields.required<String>('id'),
      kind = fields.choice('kind', ['auction_closing', 'new_listings']),
      title = fields.required<String>('title'),
      body = fields.required<String>('body'),
      expiresAt = fields.date('expires_at'),
      url = notificationListingLink(fields.nullable<String>('url')) {
    if (!notificationUuid.hasMatch(id) ||
        (fields.json['url'] != null && url == null) ||
        !expiresAt.isAfter(fields.date('created_at')) ||
        title.trim().isEmpty ||
        body.trim().isEmpty) {
      invalidResponse();
    }
    fields.list(
      'source_listing_ids',
      (id) => id is String && RegExp(r'^v1\|\d{1,40}\|\d{1,40}$').hasMatch(id)
          ? id
          : invalidResponse(),
    );
  }

  final String id, kind, title, body;
  final Uri? url;
  final DateTime expiresAt;
}

Never invalidResponse() => throw const FormatException('Érvénytelen válasz.');

Json object(Object? value) => value is Json ? value : invalidResponse();

class Fields {
  Fields(Object? value) : json = object(value);
  final Json json;

  T required<T>(String key) {
    final value = json[key];
    return value is T ? value : invalidResponse();
  }

  T? nullable<T>(String key) {
    if (!json.containsKey(key)) invalidResponse();
    return json[key] == null ? null : required<T>(key);
  }

  String choice(String key, Iterable<String> allowed) {
    final value = required<String>(key);
    return allowed.contains(value) ? value : invalidResponse();
  }

  List<T> list<T>(String key, T Function(Object?) decode) =>
      List.unmodifiable(required<List<Object?>>(key).map(decode));

  int count(String key) {
    final value = required<int>(key);
    return value >= 0 ? value : invalidResponse();
  }

  DateTime date(String key) => parseDate(required<String>(key));

  DateTime? optionalDate(String key) {
    final value = nullable<String>(key);
    return value == null ? null : parseDate(value);
  }

  static DateTime parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
      invalidResponse();
    }
    return DateTime.tryParse(value) ?? invalidResponse();
  }

  String? amount(String key) {
    final value = nullable<String>(key);
    if (value != null &&
        (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value) ||
            double.tryParse(value)?.isFinite != true)) {
      invalidResponse();
    }
    return value;
  }

  Uri? link(String key, {bool optional = false}) {
    final value = optional ? nullable<String>(key) : required<String>(key);
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      invalidResponse();
    }
    return uri;
  }
}

const itemTypes = [
  'console',
  'console_bundle',
  'mainboard',
  'not_console',
  'unsupported_model',
  'needs_review',
];
const searchStatuses = ['success', 'partial', 'error'];

class Listing {
  Listing.fromJson(Object? value) : this._(Fields(value));

  Listing._(Fields fields)
    : source = fields.choice('source', ['ebay']),
      id = fields.required<String>('source_listing_id'),
      title = fields.required<String>('title'),
      url = fields.link('url')!,
      image = fields.link('image_url', optional: true),
      model = fields.required<String>('console_model'),
      type = fields.choice('item_type', itemTypes),
      banned = fields.required<bool>('is_banned'),
      possiblyNotFaulty = fields.required<bool>('possibly_not_faulty'),
      options = fields.list(
        'buying_options',
        (value) => value is String ? value : invalidResponse(),
      ),
      price = fields.amount('price'),
      currentBid = fields.amount('current_bid'),
      bidCount = fields.nullable<int>('bid_count'),
      currency = fields.nullable<String>('currency'),
      shipping = fields.amount('shipping_cost'),
      shippingCurrency = fields.nullable<String>('shipping_currency'),
      shipsToHu = fields.choice('ships_to_hu', ['yes', 'no', 'unknown']),
      isNew = fields.json.containsKey('is_new')
          ? fields.required<bool>('is_new')
          : false,
      total = fields.amount('total_price'),
      country = fields.nullable<String>('item_country'),
      end = fields.optionalDate('end_time'),
      listedAt = fields.optionalDate('listed_at'),
      condition = fields.nullable<String>('condition'),
      status = fields.choice('status', ['ACTIVE', 'ENDED', 'UNKNOWN']),
      checkedAt = fields.date('last_checked_at'),
      faultSource = fields.choice('fault_source', ['condition', 'text']) {
    if (id.isEmpty ||
        title.trim().isEmpty ||
        (bidCount != null && bidCount! < 0) ||
        (total != null &&
            (shipping == null ||
                effectivePrice == null ||
                currency == null ||
                currency != shippingCurrency))) {
      invalidResponse();
    }
  }

  final String source, id, title, model, type, status, faultSource, shipsToHu;
  final Uri url;
  final Uri? image;
  final bool banned, possiblyNotFaulty, isNew;
  final List<String> options;
  final String? price,
      currentBid,
      currency,
      shipping,
      shippingCurrency,
      total,
      country,
      condition;
  final int? bidCount;
  final DateTime? end, listedAt;
  final DateTime checkedAt;
  bool get auction => options.contains('AUCTION');
  String? get effectivePrice => auction ? currentBid : price;

  Json toJson() => {
    'source': source,
    'source_listing_id': id,
    'title': title,
    'url': url.toString(),
    'image_url': image?.toString(),
    'console_model': model,
    'item_type': type,
    'is_banned': banned,
    'possibly_not_faulty': possiblyNotFaulty,
    'buying_options': options,
    'price': price,
    'current_bid': currentBid,
    'bid_count': bidCount,
    'currency': currency,
    'shipping_cost': shipping,
    'shipping_currency': shippingCurrency,
    'ships_to_hu': shipsToHu,
    'is_new': isNew,
    'total_price': total,
    'item_country': country,
    'end_time': end?.toIso8601String(),
    'listed_at': listedAt?.toIso8601String(),
    'condition': condition,
    'status': status,
    'last_checked_at': checkedAt.toIso8601String(),
    'fault_source': faultSource,
  };
}

class QueryStatus {
  QueryStatus.fromJson(Object? value) : this._(Fields(value));
  QueryStatus._(Fields fields)
    : query = fields.required<String>('query'),
      status = fields.choice('status', ['success', 'error']),
      error = fields.nullable<String>('error'),
      warnings = fields.list('warnings', (value) => value),
      count = fields.count('count');
  final String query, status;
  final String? error;
  final List<Object?> warnings;
  final int count;
}

class CountryStatus {
  CountryStatus.fromJson(Object? value) : this._(Fields(value));
  CountryStatus._(Fields fields)
    : country = fields.required<String>('country'),
      status = fields.choice('status', searchStatuses),
      queries = fields.list('queries', QueryStatus.fromJson);
  final String country, status;
  final List<QueryStatus> queries;
}

class ShippingCounts {
  ShippingCounts.fromJson(Object? value) : this._(Fields(value));
  ShippingCounts._(Fields fields)
    : auction = fields.count('auction'),
      fixedPrice = fields.count('fixed_price');
  final int auction, fixedPrice;
  Json toJson() => {'auction': auction, 'fixed_price': fixedPrice};
}

class ShippingBreakdown {
  ShippingBreakdown.fromJson(Object? value) : this._(Fields(value));
  ShippingBreakdown._(Fields fields)
    : byType = ShippingCounts.fromJson(fields.required<Json>('by_buying_type')),
      byCountry = Map.unmodifiable(
        fields
            .required<Json>('by_country')
            .map((key, value) => MapEntry(key, ShippingCounts.fromJson(value))),
      );
  final ShippingCounts byType;
  final Map<String, ShippingCounts> byCountry;
  Json toJson() => {
    'by_buying_type': byType.toJson(),
    'by_country': byCountry.map((key, value) => MapEntry(key, value.toJson())),
  };
}

class ShippingCheck {
  ShippingCheck.fromJson(Object? value) : this._(Fields(value));
  ShippingCheck._(Fields fields)
    : initialUnknown = fields.count('initial_unknown'),
      yes = fields.count('yes'),
      no = fields.count('no'),
      unknown = fields.count('unknown'),
      failed = fields.count('failed');

  final int initialUnknown, yes, no, unknown, failed;
  Json toJson() => {
    'initial_unknown': initialUnknown,
    'yes': yes,
    'no': no,
    'unknown': unknown,
    'failed': failed,
  };
}

class SearchResult {
  SearchResult.fromJson(Object? value) : this._(Fields(value));
  SearchResult._(Fields fields)
    : status = fields.choice('status', searchStatuses),
      listings = fields.list('listings', Listing.fromJson),
      unknownShipping = fields.list('unknown_shipping', Listing.fromJson),
      shippingBreakdown = ShippingBreakdown.fromJson(
        fields.required<Json>('unknown_shipping_breakdown'),
      ),
      countries = fields.list('countries', CountryStatus.fromJson),
      typeCounts = Map.unmodifiable({
        for (final type in itemTypes)
          type: Fields(fields.required<Json>('item_type_counts')).count(type),
      }),
      filteredNonEu = fields.count('filtered_non_eu'),
      apiCalls = fields.count('api_calls'),
      getItemCalls = fields.count('get_item_calls'),
      firstSync = fields.json.containsKey('first_sync')
          ? fields.required<bool>('first_sync')
          : false,
      shippingCheck = ShippingCheck.fromJson(
        fields.required<Json>('shipping_check'),
      ),
      dailyApiCalls = fields.count('daily_api_calls'),
      dailyBrowseCalls = fields.count('daily_browse_calls'),
      quotaWarning = fields.nullable<String>('quota_warning'),
      searchedAt = fields.date('searched_at');

  final String status;
  final List<Listing> listings, unknownShipping;
  final ShippingBreakdown shippingBreakdown;
  final List<CountryStatus> countries;
  final Map<String, int> typeCounts;
  final int filteredNonEu,
      apiCalls,
      getItemCalls,
      dailyApiCalls,
      dailyBrowseCalls;
  final ShippingCheck shippingCheck;
  final bool firstSync;
  final String? quotaWarning;
  final DateTime searchedAt;
  Iterable<Listing> get allListings => listings.followedBy(unknownShipping);

  Json toCacheJson() => {
    'status': status,
    'listings': listings.map((item) => item.toJson()).toList(),
    'unknown_shipping': unknownShipping.map((item) => item.toJson()).toList(),
    'unknown_shipping_breakdown': shippingBreakdown.toJson(),
    'countries': <Object?>[],
    'item_type_counts': typeCounts,
    'filtered_non_eu': filteredNonEu,
    'api_calls': apiCalls,
    'get_item_calls': getItemCalls,
    'first_sync': firstSync,
    'shipping_check': shippingCheck.toJson(),
    'daily_api_calls': dailyApiCalls,
    'daily_browse_calls': dailyBrowseCalls,
    'quota_warning': null,
    'searched_at': searchedAt.toIso8601String(),
  };
}

class PingResult {
  PingResult.fromJson(Object? value) : this._(Fields(value));
  PingResult._(Fields fields)
    : version = fields.required<String>('version'),
      serverTime = fields.date('server_time');
  final String version;
  final DateTime serverTime;
}

class ListingDetails {
  ListingDetails.fromJson(Object? value) : this._(Fields(value));
  ListingDetails._(Fields fields)
    : condition = fields.nullable<String>('condition_description'),
      summary = fields.nullable<String>('short_description'),
      description = fields.nullable<String>('description_text');
  final String? condition, summary, description;
}
