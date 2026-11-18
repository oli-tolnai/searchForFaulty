import 'package:material_ui/material_ui.dart';

import 'currency.dart';
import 'listings.dart';
import 'search_filters.dart';

const filterLabels = {
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
  });
  final String group;
  final GroupSearchFilter Function() read;
  final void Function(String, Object?) change;
  final VoidCallback close, clear;
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
  @override
  Widget build(BuildContext context) {
    final filter = widget.read();
    final money = MoneyScope.displayOf(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Szűrők',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: widget.close,
                icon: const Icon(Icons.close),
                tooltip: 'Szűrők bezárása',
              ),
            ],
          ),
          Text(
            deviceGroupLabels[widget.group]!,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text('Azonnal szűr, új API-hívás nélkül.'),
          chips('models', {
            for (final model in modelsByDeviceGroup[widget.group]!)
              model: model,
          }),
          for (final key in ['min_price', 'max_price', 'max_total_price'])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                key: ValueKey('${widget.group}-$key-${money.unit}'),
                initialValue: money.euroInput(filter.amount(key)),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${filterLabels[key]} (${money.unit})',
                  errorText: errors[key],
                ),
                onChanged: (text) {
                  final value = money.inputToEuro(text);
                  setState(
                    () => errors[key] = text.trim().isNotEmpty && value == null
                        ? 'Adj meg érvényes összeget.'
                        : null,
                  );
                  if (errors[key] == null) {
                    widget.change(key, text.trim().isEmpty ? null : value);
                  }
                },
              ),
            ),
          const Text('Hirdetéstípus'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'both', label: Text('Mind')),
              ButtonSegment(value: 'auction', label: Text('Aukció')),
              ButtonSegment(value: 'fixed', label: Text('Fix ár')),
            ],
            selected: {filter.values['buying_options'] as String},
            onSelectionChanged: (values) =>
                update('buying_options', values.single),
          ),
          const SizedBox(height: 12),
          select('ending_hours', {
            0: 'Nincs időkorlát',
            6: '6 órán belül',
            12: '12 órán belül',
            24: '24 órán belül',
            48: '48 órán belül',
          }, filter.values['ending_hours'] ?? 0),
          chips('countries', countries),
          for (final key in [
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
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              widget.clear();
              setState(() {});
            },
            child: const Text('Szűrők törlése'),
          ),
        ],
      ),
    );
  }
}
