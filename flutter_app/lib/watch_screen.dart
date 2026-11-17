import 'package:material_ui/material_ui.dart';

import 'alert_editor.dart' as editor;
import 'currency.dart';
import 'listing_card.dart';
import 'listings.dart';
import 'notifications.dart';
import 'sync.dart';

typedef WatchTerms = ({num threshold, int lead});

Widget _priceField(
  String label,
  MoneyDisplay display,
  num? initial,
  ValueChanged<num> save,
) {
  final shown = display.euroInput(initial);
  return TextFormField(
    initialValue: shown,
    decoration: InputDecoration(labelText: '$label (${display.unit})'),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (input) => display.inputToEuro(input) == null
        ? 'Adj meg érvényes összeget.'
        : null,
    onSaved: (input) => save(
      input == shown && initial != null ? initial : display.inputToEuro(input)!,
    ),
  );
}

Future<WatchTerms?> editWatchTerms(
  BuildContext context,
  AuctionWatch? watch, {
  MoneyDisplay? currency,
}) {
  final display = currency ?? MoneyScope.displayOf(context);
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
              'Határár',
              display,
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
    final values = await editor.editAlert(context, rule);
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PriceText(watch.threshold.toString(), 'EUR', prefix: 'Határár: '),
            Text('${watch.lead} perccel zárás előtt'),
            PriceText(bid, 'EUR', prefix: 'Utolsó ismert licit: '),
            Text(
              'Utolsó ellenőrzés: ${checked == null ? 'Nem ismert' : dateLabel(checked)}',
            ),
          ],
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
                      title: Text(rule.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rule.models.isEmpty
                                ? 'Minden modell'
                                : rule.models.join(', '),
                          ),
                          if (rule.maxPrice != null)
                            PriceText(
                              rule.maxPrice.toString(),
                              'EUR',
                              prefix: 'Vételár legfeljebb ',
                            ),
                          if (rule.maxTotal != null)
                            PriceText(
                              rule.maxTotal.toString(),
                              'EUR',
                              prefix: 'Teljes ár legfeljebb ',
                            ),
                          if (rule.maxPrice == null && rule.maxTotal == null)
                            const Text('Nincs árhatár'),
                          Text(
                            '${rule.enabled ? 'Engedélyezve' : 'Kikapcsolva'} · '
                            '${rule.includeUnknown ? 'Ismeretlen szállítással is' : 'Ismert szállítással'}',
                          ),
                        ],
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
