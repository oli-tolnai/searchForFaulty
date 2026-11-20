import 'package:material_ui/material_ui.dart';

import 'currency.dart';
import 'listings.dart';
import 'search_filters.dart';
import 'app_theme.dart';

const filterLabels = {
  'known_shipping_only': 'Csak ismert szállítási díj',
  'order': 'Rendezés',
  'models': 'Modellek',
  'min_price': 'Ár ettől',
  'max_price': 'Ár eddig',
  'max_total_price': 'Max. teljes ár',
  'buying_options': 'Hirdetéstípus',
  'ending_hours': 'Aukció zárása',
  'countries': 'Országok',
  'exclude_possibly_not_faulty': 'Lehet, hogy nem hibás elrejtése',
  'exclude_banned': 'Tiltott (banned) elrejtése',
  'include_title_faults': 'Használtként hirdetett, cím szerint hibás bevonása',
  'include_mainboards': 'Alaplapok mutatása',
  'include_third_party': 'Harmadik fél mutatása',
  'only_icloud_free': 'Csak iCloud-mentes (az eladó szerint)',
  'hide_unknown_icloud': 'Ismeretlen iCloud-állapot elrejtése',
  'gpu_vendor': 'Gyártó',
  'include_keywords': 'A cím tartalmazza bármelyiket',
  'exclude_keywords': 'A cím egyiket se tartalmazza',
};

class SearchFilterPanel extends StatefulWidget {
  const SearchFilterPanel({
    super.key,
    required this.group,
    required this.read,
    required this.change,
    required this.close,
    required this.clear,
    required this.count,
    this.alert,
    this.desktop = false,
  });
  final String group;
  final GroupSearchFilter Function() read;
  final void Function(String, Object?) change;
  final VoidCallback close, clear;
  final int Function() count;
  final VoidCallback? alert;
  final bool desktop;
  @override
  State<SearchFilterPanel> createState() => _SearchFilterPanelState();
}

class _SearchFilterPanelState extends State<SearchFilterPanel> {
  final errors = <String, String?>{};
  void update(String key, Object? value) {
    widget.change(key, value);
    setState(() {});
  }

  Widget select(String key, Map<Object, String> options, Object current) =>
      DropdownButtonFormField<Object>(
        key: ValueKey('${widget.group}-$key-$current'),
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(labelText: filterLabels[key]),
        items: options.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            update(key, value == 0 && key == 'ending_hours' ? null : value);
          }
        },
      );
  Widget chips(String key, Map<String, String> options) => ExpansionTile(
    key: PageStorageKey('${widget.group}-filter-$key'),
    tilePadding: EdgeInsets.zero,
    title: Text(
      '${filterLabels[key]} (${widget.read().strings(key).isEmpty ? 'mind' : widget.read().strings(key).length})',
    ),
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final entry in options.entries)
            FilterChip(
              label: Text(entry.value),
              selected: widget.read().strings(key).contains(entry.key),
              onSelected: (selected) {
                final values = widget.read().strings(key).toSet();
                selected ? values.add(entry.key) : values.remove(entry.key);
                update(key, values.toList());
              },
            ),
        ],
      ),
    ],
  );
  Widget amount(String key) {
    final money = MoneyScope.displayOf(context);
    final filter = widget.read();
    return TextFormField(
      key: ValueKey('${widget.group}-$key-${money.unit}'),
      initialValue: money.euroInput(filter.amount(key)),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: '${filterLabels[key]} (${money.unit})',
        errorText: errors[key],
      ),
      onChanged: (text) {
        final value = money.inputToEuro(text);
        setState(
          () => errors[key] = text.trim().isNotEmpty && value == null
              ? 'Érvénytelen összeg'
              : null,
        );
        if (errors[key] == null) {
          widget.change(key, text.trim().isEmpty ? null : value);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.read();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Szűrők · ${deviceGroupLabels[widget.group]}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!widget.desktop)
                  IconButton(
                    onPressed: widget.close,
                    icon: const Icon(Icons.close),
                    tooltip: 'Szűrők bezárása',
                  )
                else
                  TextButton(
                    onPressed: widget.clear,
                    child: const Text('Törlés'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Modell'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final model in modelsByDeviceGroup[widget.group]!)
                      FilterChip(
                        label: Text(model),
                        selected: filter.strings('models').contains(model),
                        onSelected: (selected) {
                          final values = filter.strings('models').toSet();
                          selected ? values.add(model) : values.remove(model);
                          update('models', values.toList());
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: amount('min_price')),
                    const SizedBox(width: 8),
                    Expanded(child: amount('max_price')),
                  ],
                ),
                const SizedBox(height: 16),
                amount('max_total_price'),
                const SizedBox(height: 16),
                const Text('Hirdetéstípus'),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    foregroundColor: const WidgetStatePropertyAll(Ui.text),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Ui.border
                          : Ui.surface,
                    ),
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 6),
                    ),
                    minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontFamily: 'Inter', fontSize: 12),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(value: 'both', label: Text('Mind')),
                    ButtonSegment(value: 'auction', label: Text('Aukció')),
                    ButtonSegment(value: 'fixed', label: Text('Fix ár')),
                  ],
                  selected: {filter.values['buying_options'] as String},
                  onSelectionChanged: (values) =>
                      update('buying_options', values.single),
                ),
                const SizedBox(height: 16),
                select('ending_hours', {
                  0: 'Bármikor',
                  6: '6 órán belül',
                  12: '12 órán belül',
                  24: '24 órán belül',
                  48: '48 órán belül',
                }, filter.values['ending_hours'] ?? 0),
                const SizedBox(height: 16),
                ExpansionTile(
                  key: PageStorageKey('advanced-${widget.group}'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'További beállítások',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text('Ország, kulcsszó, jelölések'),
                  children: [
                    select('order', {
                      for (final order in ListingOrder.values)
                        order.name: order.label,
                    }, filter.order.name),
                    chips('countries', countries),
                    for (final key in [
                      'known_shipping_only',
                      'exclude_possibly_not_faulty',
                      'exclude_banned',
                      'include_title_faults',
                      if (widget.group == 'consoles') 'include_mainboards',
                      if (widget.group == 'controllers') 'include_third_party',
                      if (widget.group == 'iphone') ...[
                        'only_icloud_free',
                        'hide_unknown_icloud',
                      ],
                    ])
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(filterLabels[key]!),
                        value: filter.flag(key),
                        onChanged: (value) => update(key, value),
                      ),
                    if (widget.group == 'gpu')
                      select('gpu_vendor', {
                        'both': 'Mind',
                        'NVIDIA': 'NVIDIA',
                        'AMD': 'AMD',
                      }, filter.values['gpu_vendor']!),
                    for (final key in ['include_keywords', 'exclude_keywords'])
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          key: ValueKey('${widget.group}-$key'),
                          initialValue: filter.strings(key).join(', '),
                          decoration: InputDecoration(
                            labelText: filterLabels[key],
                            helperText: 'Több kifejezés: vesszővel elválasztva',
                          ),
                          onChanged: (text) => update(
                            key,
                            text
                                .split(RegExp('[,;\\n]'))
                                .map((word) => word.trim())
                                .where((word) => word.isNotEmpty)
                                .take(20)
                                .toList(),
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.alert != null && !widget.desktop)
                  TextButton.icon(
                    onPressed: widget.alert,
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Értesítés ilyen találatokról'),
                  ),
              ],
            ),
          ),
          if (widget.desktop)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    '${widget.count()} találat',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (widget.alert != null)
                    TextButton.icon(
                      onPressed: widget.alert,
                      icon: const Icon(Icons.notifications_outlined, size: 18),
                      label: const Text(
                        'Értesítés ilyen találatokról',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (!widget.desktop) ...[
                    OutlinedButton(
                      onPressed: () {
                        widget.clear();
                        setState(() {});
                      },
                      child: const Text('Törlés'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.desktop ? null : widget.close,
                      child: Text(
                        '${widget.count()} találat mutatása',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
