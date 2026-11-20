import 'api/models.dart';
import 'listings.dart';

class GroupSearchFilter {
  GroupSearchFilter([Json values = const {}])
    : values = {
        for (final key in defaults.keys)
          key: values.containsKey(key) ? values[key] : defaults[key],
      } {
    final f = Fields(this.values);
    for (final key in [
      'models',
      'countries',
      'include_keywords',
      'exclude_keywords',
    ]) {
      f.list(key, (value) => value is String ? value : invalidResponse());
    }
    for (final key in ['min_price', 'max_price', 'max_total_price']) {
      final value = f.nullable<num>(key);
      if (value != null && (!value.isFinite || value < 0)) invalidResponse();
    }
    f.choice('buying_options', ['both', 'auction', 'fixed']);
    f.choice('gpu_vendor', ['both', 'NVIDIA', 'AMD']);
    f.choice('order', ListingOrder.values.map((value) => value.name));
    if (![null, 6, 12, 24, 48].contains(this.values['ending_hours'])) {
      invalidResponse();
    }
    for (final key in flags) {
      f.required<bool>(key);
    }
  }
  static const commonKeys = {
    'min_price',
    'max_price',
    'max_total_price',
    'buying_options',
    'ending_hours',
    'countries',
    'include_keywords',
    'exclude_keywords',
    'exclude_possibly_not_faulty',
    'exclude_banned',
    'include_title_faults',
    'order',
  };
  GroupSearchFilter get common =>
      GroupSearchFilter({for (final key in commonKeys) key: values[key]});
  static const flags = [
    'known_shipping_only',
    'exclude_possibly_not_faulty',
    'exclude_banned',
    'include_title_faults',
    'include_mainboards',
    'include_third_party',
    'only_icloud_free',
    'hide_unknown_icloud',
  ];
  static const Json defaults = {
    'models': <String>[],
    'countries': <String>[],
    'min_price': null,
    'max_price': null,
    'max_total_price': null,
    'buying_options': 'both',
    'ending_hours': null,
    'include_keywords': <String>[],
    'exclude_keywords': <String>[],
    'known_shipping_only': false,
    'exclude_possibly_not_faulty': false,
    'exclude_banned': false,
    'include_title_faults': true,
    'include_mainboards': false,
    'include_third_party': false,
    'only_icloud_free': false,
    'hide_unknown_icloud': false,
    'gpu_vendor': 'both',
    'order': 'total',
  };
  final Json values;
  GroupSearchFilter change(String key, Object? value) =>
      GroupSearchFilter({...values, key: value});
  List<String> strings(String key) => (values[key] as List).cast<String>();
  bool flag(String key) => values[key] == true;
  num? amount(String key) => values[key] as num?;
  ListingOrder get order =>
      ListingOrder.values.byName(values['order'] as String);
  bool allowsType(Listing item) =>
      inMainResults(item, mainboards: flag('include_mainboards')) ||
      flag('include_third_party') &&
          item.type == 'third_party' &&
          item.shipsToHu == 'yes';
  bool matches(Listing item, DateTime now) {
    if (!allowsType(item)) return false;
    final models = strings('models');
    if (models.isNotEmpty &&
        !item.model
            .split(' / ')
            .any(
              (model) =>
                  models.contains(model) ||
                  models.contains(
                    model.replaceFirst(
                      RegExp(r' (Disc|Digital|\(Scuf\)|\(Egyedi\))$'),
                      '',
                    ),
                  ),
            )) {
      return false;
    }
    if (strings('countries').isNotEmpty &&
        !strings('countries').contains(item.country)) {
      return false;
    }
    if (values['buying_options'] == 'auction' && !item.auction) return false;
    if (values['buying_options'] == 'fixed' &&
        !item.options.contains('FIXED_PRICE')) {
      return false;
    }
    final hours = values['ending_hours'] as int?;
    if (hours != null &&
        item.auction &&
        (item.end == null ||
            item.end!.difference(now) > Duration(hours: hours))) {
      return false;
    }
    final price = num.tryParse(item.effectivePrice ?? '');
    if (amount('min_price') case final min?) {
      if (price == null || price < min) return false;
    }
    if (amount('max_price') case final max?) {
      if (price == null || price > max) return false;
    }
    if (amount('max_total_price') case final max?) {
      if (item.shipping != null &&
          (item.total == null || num.parse(item.total!) > max)) {
        return false;
      }
    }
    if (flag('exclude_possibly_not_faulty') && item.possiblyNotFaulty ||
        flag('exclude_banned') && item.banned ||
        !flag('include_title_faults') && item.faultSource == 'title') {
      return false;
    }
    if (item.deviceGroup == 'iphone' &&
        (flag('only_icloud_free') && item.icloudStatus != 'free_by_seller' ||
            flag('hide_unknown_icloud') && item.icloudStatus == 'unknown')) {
      return false;
    }
    if (item.deviceGroup == 'gpu' &&
        values['gpu_vendor'] != 'both' &&
        !(values['gpu_vendor'] == 'NVIDIA'
            ? (item.model.startsWith('RTX') ||
                  RegExp(
                    r'nvidia|geforce|rtx',
                    caseSensitive: false,
                  ).hasMatch(item.title))
            : (item.model.startsWith('RX') ||
                  RegExp(
                    r'amd|radeon|\brx\b',
                    caseSensitive: false,
                  ).hasMatch(item.title)))) {
      return false;
    }
    final title = item.title.toLowerCase();
    if (strings('include_keywords').isNotEmpty &&
        !strings('include_keywords')
            .any((word) => title.contains(word.toLowerCase()))) {
      return false;
    }
    if (strings('exclude_keywords')
        .any((word) => title.contains(word.toLowerCase()))) {
      return false;
    }
    return true;
  }

  Map<String, Object?> get active => Map.fromEntries(
    values.entries.where(
      (entry) =>
          entry.key != 'order' &&
          (entry.value is List
              ? (entry.value as List).isNotEmpty
              : entry.value != defaults[entry.key]),
    ),
  );
  Json alert(String group) => {
    ...values,
    'name':
        '${group == 'all' ? 'Összes' : deviceGroupLabels[group]} – keresési szűrők',
    'device_groups': group == 'all' ? deviceGroups : [group],
    'enabled': true,
    'include_unknown_shipping': !flag('known_shipping_only'),
  };
}
