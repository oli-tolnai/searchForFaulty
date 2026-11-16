import 'package:material_ui/material_ui.dart';

import 'api/models.dart';
import 'listing_card.dart';
import 'listings.dart';
import 'notifications.dart';
import 'sync.dart';

typedef WatchTerms = ({num threshold, int lead});

num? _price(String? text) {
  final value = num.tryParse((text ?? '').trim().replaceAll(',', '.'));
  return value != null && value.isFinite && value >= 0 ? value : null;
}

Widget _priceField(String label, num? initial, ValueChanged<num> save) =>
    TextFormField(
      initialValue: initial?.toString(),
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (input) =>
          _price(input) == null ? 'Adj meg érvényes összeget.' : null,
      onSaved: (input) => save(_price(input)!),
    );

Future<WatchTerms?> editWatchTerms(BuildContext context, AuctionWatch? watch) {
  final form = GlobalKey<FormState>();
  num threshold = 0;
  var lead = watch?.lead ?? 120;
  final times = <int, String>{
    120: '2 órával előtte',
    60: '1 órával előtte',
    30: '30 perccel előtte',
    if (![120, 60, 30].contains(lead)) lead: '$lead perccel előtte',
  };
  return showDialog<WatchTerms>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(watch == null ? 'Aukció figyelése' : 'Figyelés szerkesztése'),
      scrollable: true,
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _priceField(
              'Határár (EUR)',
              watch?.threshold,
              (value) => threshold = value,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: lead,
              decoration: const InputDecoration(
                labelText: 'Értesítés zárás előtt',
              ),
              items: times.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) lead = value;
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Csak a zárás napján, a határár alatti ismert licitnél küldünk értesítést.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Mégse'),
        ),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            form.currentState!.save();
            Navigator.pop(context, (threshold: threshold, lead: lead));
          },
          child: const Text('Mentés'),
        ),
      ],
    ),
  );
}

Future<Json?> _editAlert(BuildContext context, AlertRule? rule) {
  final form = GlobalKey<FormState>();
  final models = {...?rule?.models};
  var enabled = rule?.enabled ?? true;
  var includeUnknown = rule?.includeUnknown ?? false;
  num maxTotal = 0;
  return showDialog<Json>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          rule == null ? 'Új értesítési szabály' : 'Szabály szerkesztése',
        ),
        scrollable: true,
        content: SizedBox(
          width: 390,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Modellek (üres kijelölésnél mindegyik)'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final model in consoleModels)
                      FilterChip(
                        label: Text(model),
                        selected: models.contains(model),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            models.add(model);
                          } else {
                            models.remove(model);
                          }
                        }),
                      ),
                  ],
                ),
                _priceField(
                  'Max. teljes ár (EUR)',
                  rule?.maxTotal,
                  (value) => maxTotal = value,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ismeretlen szállítás bevonása'),
                  subtitle: const Text(
                    'Ilyenkor a vételár vagy a licit számít.',
                  ),
                  value: includeUnknown,
                  onChanged: (value) => setState(() => includeUnknown = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Szabály engedélyezve'),
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              form.currentState!.save();
              Navigator.pop(context, {
                'models': models.toList(),
                'max_total_price': maxTotal,
                'include_unknown_shipping': includeUnknown,
                'enabled': enabled,
              });
            },
            child: const Text('Mentés'),
          ),
        ],
      ),
    ),
  );
}

class WatchScreen extends StatelessWidget {
  const WatchScreen({
    super.key,
    required this.shared,
    required this.now,
    this.navigation,
  });
  final SharedState shared;
  final DateTime now;
  final Widget? navigation;

  Future<void> editRule(BuildContext context, AlertRule? rule) async {
    final values = await _editAlert(context, rule);
    if (values != null && context.mounted) await shared.saveAlert(rule, values);
  }

  Future<void> changeWatch(BuildContext context, AuctionWatch watch) async {
    final terms = await editWatchTerms(context, watch);
    if (terms != null && context.mounted) {
      await shared.updateWatch(watch, terms.threshold, terms.lead);
    }
  }

  String statusOf(AuctionWatch watch) =>
      watch.end.isAfter(now) ? watch.status : 'ended';

  Widget watchCard(BuildContext context, AuctionWatch watch) {
    final checked = watch.checked;
    final bid = checked != null && now.difference(checked) < maxListingAge
        ? watch.bid
        : null;
    return Card(
      child: ListTile(
        title: Text(watch.title),
        subtitle: Text(
          'Határár: ${watch.threshold} € · ${watch.lead} perccel zárás előtt\n'
          'Utolsó ismert licit: ${money(bid, 'EUR')}\n'
          'Utolsó ellenőrzés: ${checked == null ? 'Nem ismert' : dateLabel(checked)}',
        ),
        onTap: () => openExternal(context, watch.url),
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: 'Figyelés szerkesztése',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => changeWatch(context, watch),
            ),
            IconButton(
              tooltip: 'Figyelés törlése',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => shared.removeWatch(watch),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final watches = shared.watches.toList()
      ..sort((a, b) => a.end.compareTo(b.end));
    final rules = shared.alerts.toList();
    const statuses = {
      'active': 'Aktív',
      'notified': 'Értesített',
      'ended': 'Lezárt',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Figyelés'),
        actions: [
          IconButton(
            tooltip: 'Szinkronizálás',
            onPressed: shared.sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      bottomNavigationBar: navigation,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (shared.pending)
                  const Text('Nem szinkronizált változások')
                else if (shared.syncFailed)
                  const Text('A szinkron nem érhető el.'),
                if (watches.isEmpty)
                  const Text('Még nincsenek figyelt aukciók.'),
                for (final entry in statuses.entries)
                  if (watches.any((watch) => statusOf(watch) == entry.key)) ...[
                    const SizedBox(height: 8),
                    Text(entry.value, style: theme.textTheme.titleLarge),
                    for (final watch in watches.where(
                      (watch) => statusOf(watch) == entry.key,
                    ))
                      watchCard(context, watch),
                  ],
                const SizedBox(height: 24),
                Text(
                  'Értesítés új találatról',
                  style: theme.textTheme.titleLarge,
                ),
                if (rules.isEmpty) const Text('Még nincs értesítési szabály.'),
                for (final rule in rules)
                  Card(
                    child: ListTile(
                      title: Text(
                        rule.models.isEmpty
                            ? 'Minden modell'
                            : rule.models.join(', '),
                      ),
                      subtitle: Text(
                        'Legfeljebb ${rule.maxTotal} €\n'
                        '${rule.enabled ? 'Engedélyezve' : 'Kikapcsolva'} · '
                        '${rule.includeUnknown ? 'Ismeretlen szállítással is' : 'Ismert szállítással'}',
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Szabály szerkesztése',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => editRule(context, rule),
                          ),
                          IconButton(
                            tooltip: 'Szabály törlése',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => shared.removeAlert(rule),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => editRule(context, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Új szabály'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
