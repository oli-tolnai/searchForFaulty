import 'package:material_ui/material_ui.dart';

import 'api/models.dart';
import 'currency.dart';
import 'listings.dart';
import 'notifications.dart';
import 'search_filters.dart';
import 'search_filter_panel.dart' show filterLabels;

Future<Json?> editAlert(
  BuildContext context,
  AlertRule? rule, {
  bool newRule = false,
}) => showDialog<Json>(
  context: context,
  builder: (_) => _AlertEditor(
    rule: rule,
    money: MoneyScope.displayOf(context),
    isNew: newRule,
  ),
);

class _AlertEditor extends StatefulWidget {
  const _AlertEditor({
    required this.rule,
    required this.money,
    this.isNew = false,
  });
  final bool isNew;
  final AlertRule? rule;
  final MoneyDisplay money;
  @override
  State<_AlertEditor> createState() => _AlertEditorState();
}

class _AlertEditorState extends State<_AlertEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.rule?.name ?? 'Értesítési szabály',
  );
  late final minPrice = TextEditingController(
    text: widget.money.euroInput(widget.rule?.advanced['min_price'] as num?),
  );
  late final advanced = <String, Object?>{
    ...GroupSearchFilter.defaults,
    ...?widget.rule?.advanced,
  };
  late final maxPrice = TextEditingController(
    text: widget.money.euroInput(widget.rule?.maxPrice),
  );
  late final maxTotal = TextEditingController(
    text: widget.money.euroInput(widget.rule?.maxTotal),
  );
  late final include = TextEditingController(
    text: widget.rule?.includeKeywords.join(', '),
  );
  late final exclude = TextEditingController(
    text: widget.rule?.excludeKeywords.join(', '),
  );
  late final models = {...?widget.rule?.models};
  late final groups = {
    ...?widget.rule?.groups,
    if (widget.rule == null) ...['consoles', 'controllers'],
  };
  late final selectedCountries = {...?widget.rule?.countries};
  late var buying = widget.rule?.buying ?? 'both';
  late var ending = widget.rule?.endingHours ?? 0;
  late bool knownOnly = !(widget.rule?.includeUnknown ?? false);
  late bool excludeNew = widget.rule?.excludePossiblyNotFaulty ?? true;
  late bool excludeBanned = widget.rule?.excludeBanned ?? false;
  late bool titleFaults = widget.rule?.includeTitleFaults ?? true;
  late bool enabled = widget.rule?.enabled ?? true;

  @override
  void dispose() {
    for (final input in [
      name,
      minPrice,
      maxPrice,
      maxTotal,
      include,
      exclude,
    ]) {
      input.dispose();
    }
    super.dispose();
  }

  List<String> keywords(String text) => text
      .split(RegExp('[,;\\n]'))
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toSet()
      .toList();

  num? euroValue(TextEditingController input, num? previous) {
    if (input.text.trim().isEmpty) return null;
    return previous != null && input.text == widget.money.euroInput(previous)
        ? previous
        : widget.money.inputToEuro(input.text);
  }

  Widget amount(TextEditingController input, String label) => TextFormField(
    controller: input,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: '$label (${widget.money.unit})',
      helperText: 'Üresen nincs árhatár',
    ),
    validator: (value) =>
        value!.trim().isNotEmpty && widget.money.inputToEuro(value) == null
        ? 'Adj meg érvényes összeget.'
        : null,
  );

  Widget toggle(String label, bool value, ValueChanged<bool> change) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: (value) => setState(() => change(value)),
      );

  Widget keywordInput(TextEditingController input, String label) =>
      TextFormField(
        controller: input,
        decoration: InputDecoration(
          labelText: label,
          helperText: 'Vesszővel elválasztva, legfeljebb 20 szó vagy kifejezés',
        ),
        validator: (_) =>
            keywords(input.text).length > 20 ||
                keywords(input.text).any((word) => word.length > 100)
            ? 'Legfeljebb 20, egyenként 100 karakteres kifejezést adj meg.'
            : null,
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.rule == null || widget.isNew
          ? 'Új értesítési szabály'
          : 'Szabály szerkesztése',
    ),
    scrollable: true,
    content: SizedBox(
      width: 490,
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Név'),
              validator: (value) =>
                  value!.trim().isEmpty ? 'Adj nevet a szabálynak.' : null,
            ),
            const Text('Eszközcsoportok'),
            Wrap(
              spacing: 8,
              children: [
                for (final (id, label) in deviceGroupLabels.entries.map(
                  (entry) => (entry.key, entry.value),
                ))
                  FilterChip(
                    label: Text(label),
                    selected: groups.contains(id),
                    onSelected: groups.length == 1 && groups.contains(id)
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              groups.add(id);
                            } else {
                              groups.remove(id);
                            }
                          }),
                  ),
              ],
            ),
            const Text('Modellek (üres kijelölésnél mindegyik)'),
            Wrap(
              spacing: 8,
              children: [
                for (final model in groups.expand(
                  (group) => modelsByDeviceGroup[group]!,
                ))
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
            DropdownButtonFormField<String>(
              initialValue: buying,
              decoration: const InputDecoration(labelText: 'Hirdetéstípus'),
              items: const [
                DropdownMenuItem(value: 'both', child: Text('Mind')),
                DropdownMenuItem(value: 'auction', child: Text('Csak aukció')),
                DropdownMenuItem(value: 'fixed', child: Text('Csak fix ár')),
              ],
              onChanged: (value) => setState(() => buying = value!),
            ),
            amount(minPrice, 'Min. vételár vagy aktuális licit'),
            amount(maxPrice, 'Max. vételár vagy aktuális licit'),
            amount(maxTotal, 'Max. teljes ár'),
            toggle(
              'Csak ismert szállítási díjjal',
              knownOnly,
              (value) => knownOnly = value,
            ),
            DropdownButtonFormField<int>(
              initialValue: ending,
              decoration: const InputDecoration(labelText: 'Aukciók zárása'),
              items: [
                for (final hours in [0, 6, 12, 24, 48])
                  DropdownMenuItem(
                    value: hours,
                    child: Text(
                      hours == 0 ? 'Nincs időkorlát' : '$hours órán belül',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => ending = value!),
            ),
            keywordInput(include, 'A cím tartalmazza bármelyiket'),
            keywordInput(exclude, 'A cím egyiket se tartalmazza'),
            ExpansionTile(
              title: Text(
                selectedCountries.isEmpty
                    ? 'Országok: mind'
                    : 'Országok: ${selectedCountries.length}',
              ),
              tilePadding: EdgeInsets.zero,
              children: [
                TextButton(
                  onPressed: () => setState(selectedCountries.clear),
                  child: const Text('Minden ország'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in countries.entries)
                      FilterChip(
                        label: Text(entry.value),
                        selected: selectedCountries.contains(entry.key),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            selectedCountries.add(entry.key);
                          } else {
                            selectedCountries.remove(entry.key);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
            toggle(
              '„Lehet, hogy nem hibás” tételek kizárása',
              excludeNew,
              (value) => excludeNew = value,
            ),
            toggle(
              'Tiltott (banned) tételek kizárása',
              excludeBanned,
              (value) => excludeBanned = value,
            ),
            toggle(
              'Használtként hirdetett, cím szerint hibás tételek bevonása',
              titleFaults,
              (value) => titleFaults = value,
            ),
            for (final key in [
              if (groups.contains('consoles')) 'include_mainboards',
              if (groups.contains('controllers')) 'include_third_party',
              if (groups.contains('iphone')) ...[
                'only_icloud_free',
                'hide_unknown_icloud',
              ],
            ])
              toggle(
                filterLabels[key]!,
                advanced[key] == true,
                (value) => advanced[key] = value,
              ),
            if (groups.contains('gpu'))
              DropdownButtonFormField<String>(
                initialValue: advanced['gpu_vendor'] as String,
                decoration: const InputDecoration(labelText: 'Gyártó'),
                items: ['both', 'NVIDIA', 'AMD']
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value == 'both' ? 'Mind' : value),
                      ),
                    )
                    .toList(),
                onChanged: (value) => advanced['gpu_vendor'] = value,
              ),
            toggle('Szabály engedélyezve', enabled, (value) => enabled = value),
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
          final available = groups
              .expand((group) => modelsByDeviceGroup[group]!)
              .toSet();
          Navigator.pop(context, {
            ...advanced,
            'min_price': euroValue(
              minPrice,
              widget.rule?.advanced['min_price'] as num?,
            ),
            'name': name.text.trim(),
            'device_groups': groups.toList(),
            'models': models.where(available.contains).toList(),
            'buying_options': buying,
            'max_price': euroValue(maxPrice, widget.rule?.maxPrice),
            'max_total_price': euroValue(maxTotal, widget.rule?.maxTotal),
            'known_shipping_only': knownOnly,
            'include_unknown_shipping': !knownOnly,
            'ending_hours': ending == 0 ? null : ending,
            'include_keywords': keywords(include.text),
            'exclude_keywords': keywords(exclude.text),
            'countries': selectedCountries.toList(),
            'exclude_possibly_not_faulty': excludeNew,
            'exclude_banned': excludeBanned,
            'include_title_faults': titleFaults,
            'enabled': enabled,
          });
        },
        child: const Text('Mentés'),
      ),
    ],
  );
}
