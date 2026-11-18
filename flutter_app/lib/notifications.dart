import 'api/models.dart';
import 'listings.dart';

final countryCodes = countries.keys.toSet();

class AuctionWatch {
  AuctionWatch(Json row) : this._(Fields(row));

  AuctionWatch._(Fields fields)
    : source = fields.choice('source', ['ebay']),
      id = fields.required<String>('source_listing_id'),
      title = fields.required<String>('title'),
      url = fields.link('url')!,
      threshold = notificationAmount(fields, 'threshold'),
      lead = fields.count('lead_minutes'),
      status = fields.choice('status', [
        'active',
        'notified',
        'ended',
        'cancelled',
      ]),
      bid = fields.amount('last_bid'),
      checked = fields.optionalDate('last_checked_at'),
      end = fields.date('end_time') {
    if (lead < 1 || lead > 1440) invalidResponse();
  }

  final String source, id, title, status;
  final Uri url;
  final num threshold;
  final int lead;
  final String? bid;
  final DateTime? checked;
  final DateTime end;
}

class AlertRule {
  AlertRule(Json row) : this._(Fields(row));

  AlertRule._(Fields fields)
    : advanced = {
        'min_price': optionalAlertAmount(fields, 'min_price'),
        for (final key in [
          'include_mainboards',
          'include_third_party',
          'only_icloud_free',
          'hide_unknown_icloud',
        ])
          key: fields.json[key] ?? false,
        'gpu_vendor': fields.json['gpu_vendor'] ?? 'both',
      },
      id = fields.required<String>('id'),
      name = fields.json['name'] == null
          ? 'Értesítési szabály'
          : fields.required<String>('name'),
      models = fields.list(
        'models',
        (value) => allDeviceModels.contains(value) && value is String
            ? value
            : invalidResponse(),
      ),
      groups = fields.json['device_groups'] == null
          ? modelsByDeviceGroup.keys.where((group) {
              final models = fields.required<List<Object?>>('models');
              return models.isEmpty
                  ? ['consoles', 'controllers'].contains(group)
                  : models.any(modelsByDeviceGroup[group]!.contains);
            }).toList()
          : fields.list(
              'device_groups',
              (value) => deviceGroups.contains(value) && value is String
                  ? value
                  : invalidResponse(),
            ),
      buying = fields.json['buying_options'] == null
          ? 'both'
          : fields.choice('buying_options', ['both', 'auction', 'fixed']),
      maxPrice = optionalAlertAmount(fields, 'max_price'),
      maxTotal = optionalAlertAmount(fields, 'max_total_price'),
      includeUnknown = fields.json['known_shipping_only'] == null
          ? fields.required<bool>('include_unknown_shipping')
          : !fields.required<bool>('known_shipping_only'),
      endingHours = fields.json['ending_hours'] == null
          ? null
          : fields.required<int>('ending_hours'),
      includeKeywords = alertWords(fields, 'include_keywords'),
      excludeKeywords = alertWords(fields, 'exclude_keywords'),
      countries = fields.json['countries'] == null
          ? []
          : fields.list(
              'countries',
              (value) => value is String && countryNames.contains(value)
                  ? value
                  : invalidResponse(),
            ),
      excludePossiblyNotFaulty =
          fields.json['exclude_possibly_not_faulty'] == null
          ? true
          : fields.required<bool>('exclude_possibly_not_faulty'),
      excludeBanned = fields.json['exclude_banned'] == null
          ? false
          : fields.required<bool>('exclude_banned'),
      includeTitleFaults = fields.json['include_title_faults'] == null
          ? true
          : fields.required<bool>('include_title_faults'),
      enabled = fields.required<bool>('enabled') {
    for (final key in [
      'include_mainboards',
      'include_third_party',
      'only_icloud_free',
      'hide_unknown_icloud',
    ]) {
      if (advanced[key] is! bool) invalidResponse();
    }
    if (!['both', 'NVIDIA', 'AMD'].contains(advanced['gpu_vendor'])) {
      invalidResponse();
    }
    if (name.trim().isEmpty ||
        name.length > 120 ||
        groups.isEmpty ||
        ![null, 6, 12, 24, 48].contains(endingHours)) {
      invalidResponse();
    }
  }

  final Json advanced;
  static final countryNames = countryCodes;
  final String id, name, buying;
  final List<String> models,
      groups,
      includeKeywords,
      excludeKeywords,
      countries;
  final num? maxTotal, maxPrice;
  final int? endingHours;
  final bool includeUnknown,
      enabled,
      excludePossiblyNotFaulty,
      excludeBanned,
      includeTitleFaults;

  Json get values => {
    ...advanced,
    'name': name,
    'models': models,
    'device_groups': groups,
    'buying_options': buying,
    'max_price': maxPrice,
    'max_total_price': maxTotal,
    'include_unknown_shipping': includeUnknown,
    'known_shipping_only': !includeUnknown,
    'ending_hours': endingHours,
    'include_keywords': includeKeywords,
    'exclude_keywords': excludeKeywords,
    'countries': countries,
    'exclude_possibly_not_faulty': excludePossiblyNotFaulty,
    'exclude_banned': excludeBanned,
    'include_title_faults': includeTitleFaults,
    'enabled': enabled,
  };
}

num? optionalAlertAmount(Fields fields, String key) {
  return fields.json[key] == null ? null : notificationAmount(fields, key);
}

List<String> alertWords(Fields fields, String key) {
  if (fields.json[key] == null) return [];
  final words = fields.list(
    key,
    (value) => value is String && value.trim().isNotEmpty && value.length <= 100
        ? value
        : invalidResponse(),
  );
  if (words.length > 20) invalidResponse();
  return words;
}

num notificationAmount(Fields fields, String key) {
  final value = fields.required<num>(key);
  return value.isFinite && value >= 0 ? value : invalidResponse();
}
