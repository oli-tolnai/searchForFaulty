import 'api/models.dart';
import 'listings.dart';

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
    : id = fields.required<String>('id'),
      models = fields.list('models', (model) {
        if (model is! String || !consoleModels.contains(model)) {
          invalidResponse();
        }
        return model;
      }),
      maxTotal = notificationAmount(fields, 'max_total_price'),
      includeUnknown = fields.required<bool>('include_unknown_shipping'),
      enabled = fields.required<bool>('enabled');

  final String id;
  final List<String> models;
  final num maxTotal;
  final bool includeUnknown, enabled;

  Json get values => {
    'models': models,
    'max_total_price': maxTotal,
    'include_unknown_shipping': includeUnknown,
    'enabled': enabled,
  };
}

num notificationAmount(Fields fields, String key) {
  final value = fields.required<num>(key);
  return value.isFinite && value >= 0 ? value : invalidResponse();
}
