import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'alert_editor.dart' as alerts;
import 'notifications.dart';
import 'currency.dart';
import 'group_results.dart';
import 'listings.dart';
import 'search_filter_panel.dart';
import 'search_filters.dart';
import 'sync.dart';

const groupIcons = {
  'all': Icons.dashboard_outlined,
  'consoles': Icons.sports_esports_outlined,
  'controllers': Icons.gamepad_outlined,
  'switch': Icons.sports_esports,
  'steam_deck': Icons.videogame_asset_outlined,
  'iphone': Icons.phone_iphone,
  'gpu': Icons.memory,
};

class SearchWorkspace extends StatefulWidget {
  const SearchWorkspace({
    super.key,
    required this.results,
    required this.search,
    required this.details,
    required this.card,
    required this.persist,
    required this.clock,
    this.shared,
    this.navigation,
    this.config,
    this.onSettings,
    this.sanitize,
  });
  final GroupResults results;
  final Future<SearchResult> Function(Set<String>) search;
  final Future<ListingDetails> Function(String) details;
  final Widget Function(
    Listing,
    DateTime,
    Future<ListingDetails> Function(String),
    bool,
  )
  card;
  final Future<void> Function(GroupResults) persist;
  final DateTime Function() clock;
  final SharedState? shared;
  final Widget? navigation;
  final Future<PingResult> Function()? config;
  final VoidCallback? onSettings;
  final String Function(String)? sanitize;
  @override
  State<SearchWorkspace> createState() => _SearchWorkspaceState();
}

class _SearchWorkspaceState extends State<SearchWorkspace> {
  String tab = 'all';
  String filterGroup = 'consoles';
  HiddenGroup? hidden;
  bool busy = false, showFilters = false, confirming = false;
  int filterEpoch = 0;
  String? error;
  final failures = <String, SearchResult>{};
  PingResult? configuration;
  final localFilters = <String, GroupSearchFilter>{};
  final tabKeys = {
    for (final group in ['all', ...deviceGroups]) group: GlobalKey(),
  };
  final selected = {'consoles', 'controllers'};
  Timer? timer;
  late final cachedGroups = widget.results.groups.keys.toSet();
  List<String> get visibleGroups =>
      widget.shared?.visibleSearchGroups ?? deviceGroups;
  List<String> get scopedGroups => tab == 'all' ? visibleGroups : [tab];
  @override
  void initState() {
    super.initState();
    selected
      ..clear()
      ..addAll(
        widget.shared?.selectedSearchGroups ?? ['consoles', 'controllers'],
      );
    selected.retainAll(visibleGroups);
    if (selected.isEmpty) selected.add(visibleGroups.first);
    filterGroup = visibleGroups.first;
    widget.shared?.addListener(changed);
    scheduleRefresh();
    unawaited(loadConfig());
  }

  void scheduleRefresh() {
    timer?.cancel();
    final now = widget.clock();
    var next = const Duration(minutes: 1);
    for (final item in widget.results.groups.values.expand(
      (result) => result.allListings,
    )) {
      for (final boundary in [
        item.checkedAt.add(uncheckedAfter),
        item.checkedAt.add(maxListingAge),
        if (item.end != null) item.end!,
      ]) {
        final delay = boundary.difference(now);
        if (delay > Duration.zero && delay < next) next = delay;
      }
      if (item.auction &&
          visibleListing(item, now) &&
          next > const Duration(seconds: 1)) {
        next = const Duration(seconds: 1);
      }
    }
    timer = Timer(next, () {
      if (mounted) {
        setState(() {});
        scheduleRefresh();
      }
    });
  }

  String statusLabel(String value) => switch (value) {
    'success' => 'Sikeres',
    'partial' => 'Részleges',
    _ => 'Hiba',
  };
  String tabLabel(String group) => switch (group) {
    'consoles' => 'Konzol',
    'controllers' => 'Kontroller',
    _ => deviceGroupLabels[group]!,
  };
  String chipValue(String key, Object? value) {
    if (value is bool) return value ? 'Be' : 'Ki';
    if (value is List) {
      return value
          .map(
            (entry) =>
                key == 'countries' ? countryName(entry as String) : entry,
          )
          .join(', ');
    }
    if (['min_price', 'max_price', 'max_total_price'].contains(key)) {
      return MoneyScope.displayOf(context).format(value.toString(), 'EUR');
    }
    if (key == 'buying_options') {
      return value == 'auction' ? 'Aukció' : 'Fix ár';
    }
    if (key == 'ending_hours') return '$value órán belül';
    return value.toString();
  }

  @override
  void didUpdateWidget(covariant SearchWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shared != widget.shared) {
      oldWidget.shared?.removeListener(changed);
      widget.shared?.addListener(changed);
      changed();
      unawaited(loadConfig());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.shared?.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (mounted) {
      setState(() {
        final synced = widget.shared?.selectedSearchGroups;
        if (synced != null) {
          selected
            ..clear()
            ..addAll(synced);
        }
        selected.retainAll(visibleGroups);
        if (selected.isEmpty) selected.add(visibleGroups.first);
        if (tab != 'all' && !visibleGroups.contains(tab)) tab = 'all';
        if (!visibleGroups.contains(filterGroup)) {
          filterGroup = visibleGroups.first;
        }
      });
    }
  }

  Future<void> loadConfig() async {
    try {
      final config = await widget.config?.call();
      if (mounted) setState(() => configuration = config);
    } on Exception {
      /* Searches remain available when config is offline. */
    }
  }

  GroupSearchFilter filter(String group) =>
      widget.shared?.searchFilter(group) ??
      localFilters[group] ??
      GroupSearchFilter();
  void changeFilter(String group, String key, Object? value) {
    final next = filter(group).change(key, value);
    setState(() => localFilters[group] = next);
    unawaited(widget.shared?.setSearchFilter(group, next));
  }

  void clearFilter(String group) {
    setState(() {
      localFilters[group] = GroupSearchFilter();
      filterEpoch++;
    });
    unawaited(widget.shared?.setSearchFilter(group, GroupSearchFilter()));
  }

  Widget filterPanel(VoidCallback close) {
    final group = filterGroup;
    return SearchFilterPanel(
      key: ValueKey('$group-$filterEpoch'),
      group: group,
      read: () => filter(group),
      change: (key, value) => changeFilter(group, key, value),
      close: close,
      clear: () => clearFilter(group),
    );
  }

  int? estimate(Iterable<String> groups) =>
      configuration?.estimatedSearchCalls(groups);
  int? get todayUsage {
    int? used = configuration?.dailyApiCalls;
    final now = widget.clock();
    for (final result in widget.results.groups.values) {
      if (result.searchedAt.toLocal().year == now.year &&
          result.searchedAt.toLocal().month == now.month &&
          result.searchedAt.toLocal().day == now.day &&
          (used == null || result.dailyApiCalls > used)) {
        used = result.dailyApiCalls;
      }
    }
    return used;
  }

  List<Listing> get active {
    final now = widget.clock();
    final unique = <String, Listing>{};
    for (final group in scopedGroups) {
      for (final item
          in widget.results.groups[group]?.allListings ?? <Listing>[]) {
        if (visibleListing(item, now) &&
            widget.shared?.isHidden(item) != true) {
          unique['${item.source}:${item.id}'] = item;
        }
      }
    }
    return unique.values.toList();
  }

  List<Listing> get shown {
    final now = widget.clock();
    final items = active
        .where((item) => filter(item.deviceGroup).matches(item, now))
        .toList();
    final order = filter(tab == 'all' ? filterGroup : tab).order;
    items.sort((a, b) {
      int compare(Comparable? x, Comparable? y, {bool descending = false}) {
        if (x == null) return y == null ? 0 : 1;
        if (y == null) return -1;
        return descending ? y.compareTo(x) : x.compareTo(y);
      }

      final value = switch (order) {
        ListingOrder.total => compare(
          num.tryParse(a.total ?? ''),
          num.tryParse(b.total ?? ''),
        ),
        ListingOrder.cheap => compare(
          num.tryParse(a.effectivePrice ?? ''),
          num.tryParse(b.effectivePrice ?? ''),
        ),
        ListingOrder.expensive => compare(
          num.tryParse(a.effectivePrice ?? ''),
          num.tryParse(b.effectivePrice ?? ''),
          descending: true,
        ),
        ListingOrder.newest => compare(
          a.listedAt,
          b.listedAt,
          descending: true,
        ),
        ListingOrder.ending => compare(
          a.auction ? a.end : null,
          b.auction ? b.end : null,
        ),
      };
      return value == 0 ? a.id.compareTo(b.id) : value;
    });
    return items;
  }

  Future<void> refreshGroups(Set<String> groups) async {
    if (busy || confirming || groups.isEmpty) return;
    if (tab == 'all') {
      confirming = true;
      await loadConfig();
      confirming = false;
      if (!mounted) return;
    }
    final cost = estimate(groups);
    if (tab == 'all' && (cost == null || cost > 150)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Több csoport frissítése'),
          content: Text(
            'Becsült hívásszám: ${cost ?? 'Nem ismert'}. Mai felhasználás: ${todayUsage ?? 'Nem ismert'}. A lapozás további hívásokat igényelhet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Mégse'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Frissítés'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.shared?.sync();
      for (final group in groups) {
        widget.shared?.searchedAgain(
          widget.results.groups[group]?.allListings ?? [],
        );
        try {
          final result = await widget.search({group});
          if (!mounted) return;
          if (result.status == 'error') {
            failures[group] = result;
            setState(
              () => error =
                  '${deviceGroupLabels[group]}: minden lekérdezés hibás. A korábbi eredmények megmaradtak.',
            );
          } else {
            failures.remove(group);
            setState(
              () => widget.results.groups.addAll(
                GroupResults.split(result, [group]),
              ),
            );
            cachedGroups.remove(group);
            await widget.persist(widget.results);
            scheduleRefresh();
          }
          if (result.exchangeRate case final rate?) {
            widget.shared?.acceptExchangeRate(rate);
          }
        } on AppFailure catch (failure) {
          if (mounted) {
            setState(
              () => error = '${deviceGroupLabels[group]}: ${failure.message}',
            );
          }
        }
      }
      unawaited(widget.shared?.sync());
    } on AppFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } on Exception {
      if (mounted) {
        setState(() => error = 'A keresés vagy a helyi mentés sikertelen.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<ListingDetails> details(String id) async {
    final value = await widget.details(id);
    if (mounted) {
      setState(() => widget.results.details(id, value));
      await widget.persist(widget.results);
    }
    return value;
  }

  void openFilters(bool wide) {
    if (tab != 'all') filterGroup = tab;
    if (wide) {
      setState(() => showFilters = !showFilters);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .92,
        child: MoneyScope(
          display: MoneyScope.displayOf(this.context),
          toggle: MoneyScope.maybeOf(this.context)?.toggle,
          child: filterPanel(() => Navigator.pop(context)),
        ),
      ),
    );
  }

  Future<void> createAlert() async {
    final group = tab == 'all' ? filterGroup : tab;
    final draft = AlertRule({
      'id': 'draft-search-alert',
      ...filter(group).alert(group),
    });
    final values = await alerts.editAlert(context, draft, newRule: true);
    if (values != null && mounted) await widget.shared?.saveAlert(null, values);
  }

  Widget banner(String text, {Widget? action, bool warning = false}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warning
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            ?action,
          ],
        ),
      );
  Widget cardGrid(List<Listing> items, double width) {
    final columns = width >= 1050
        ? 3
        : width >= 680
        ? 2
        : 1;
    return Column(
      children: [
        for (var index = 0; index < items.length; index += columns)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var offset = 0; offset < columns; offset++) ...[
                  if (offset > 0) const SizedBox(width: 10),
                  Expanded(
                    child: index + offset < items.length
                        ? widget.card(
                            items[index + offset],
                            widget.clock(),
                            details,
                            tab == 'all',
                          )
                        : const SizedBox(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget tabs() {
    return SingleChildScrollView(
      key: const PageStorageKey('device-group-tabs'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final group in ['all', ...visibleGroups])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: tabKeys[group],
                avatar: Icon(groupIcons[group], size: 18),
                selected: tab == group,
                onSelected: (_) => setState(() {
                  tab = group;
                  hidden = null;
                  if (group != 'all') filterGroup = group;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final target = tabKeys[group]?.currentContext;
                    if (mounted && target != null) {
                      Scrollable.ensureVisible(target, alignment: .5);
                    }
                  });
                }),
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group == 'all' ? 'Összes' : tabLabel(group)),
                    Text(
                      group == 'all'
                          ? '${activeFor(visibleGroups).length} találat'
                          : '${activeFor([group]).length} · ${widget.results.groups[group] == null ? 'Még nem kerestél' : dateLabel(widget.results.groups[group]!.searchedAt)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (group == 'all')
                      Text(
                        widget.results.groups.isEmpty
                            ? 'Még nem kerestél'
                            : 'Frissítve: ${dateLabel(widget.results.groups.values.map((r) => r.searchedAt).reduce((a, b) => a.isAfter(b) ? a : b))}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Listing> activeFor(Iterable<String> groups) => groups
      .expand(
        (group) => widget.results.groups[group]?.allListings ?? <Listing>[],
      )
      .where(
        (item) =>
            visibleListing(item, widget.clock()) &&
            widget.shared?.isHidden(item) != true &&
            filter(item.deviceGroup).allowsType(item),
      )
      .toList();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final listings = shown;
      final runs = {
        for (final group in scopedGroups)
          if (widget.results.groups[group] != null)
            group: widget.results.groups[group]!,
      };
      final calls = runs.values.fold(0, (sum, result) => sum + result.apiCalls);
      final last = runs.isEmpty
          ? null
          : runs.values
                .map((r) => r.searchedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);
      final mainCount = active
          .where((item) => filter(item.deviceGroup).allowsType(item))
          .length;
      final hiddenRows = active
          .where(
            (item) =>
                !inMainResults(
                  item,
                  mainboards: filter(item.deviceGroup)
                      .flag('include_mainboards'),
                ) &&
                !(filter(item.deviceGroup).flag('include_third_party') &&
                    item.type == 'third_party' &&
                    item.shipsToHu == 'yes'),
          )
          .toList();
      final cost = estimate(
        tab == 'all' ? selected.where(visibleGroups.contains) : [tab],
      );
      Widget body(double width) {
        final headers = <Widget>[
          tabs(),
          if (scopedGroups.any(cachedGroups.contains))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Korábban mentett eredmény is látható – a csoportok frissessége eltérhet.',
              ),
            ),
          const SizedBox(height: 18),
          if (hidden == null) ...[
            if (tab == 'all')
              Wrap(
                spacing: 8,
                children: [
                  for (final group in visibleGroups)
                    FilterChip(
                      label: Text(deviceGroupLabels[group]!),
                      selected: selected.contains(group),
                      onSelected: (value) {
                        if (!value && selected.length == 1) return;
                        setState(
                          () => value
                              ? selected.add(group)
                              : selected.remove(group),
                        );
                        unawaited(
                          widget.shared?.setSelectedSearchGroups(
                            selected.toList(),
                          ),
                        );
                      },
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => refreshGroups(
                          tab == 'all'
                              ? selected.where(visibleGroups.contains).toSet()
                              : {tab},
                        ),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    '${tab == 'all' ? 'Összes kijelölt frissítése' : 'Keresés'} · ${cost == null ? 'Becslés nem ismert' : '~$cost hívás'}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => openFilters(wide),
                  icon: const Icon(Icons.tune),
                  label: const Text('Szűrők'),
                ),
                if (widget.shared != null)
                  TextButton.icon(
                    onPressed: createAlert,
                    icon: const Icon(Icons.add_alert_outlined),
                    label: const Text('Értesítés ilyen találatokról'),
                  ),
                if (tab == 'all')
                  DropdownButton<String>(
                    value: filterGroup,
                    items: visibleGroups
                        .map(
                          (group) => DropdownMenuItem(
                            value: group,
                            child: Text('${deviceGroupLabels[group]} szűrői'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => filterGroup = value!),
                  ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const Text(
                'Keresés folyamatban… a többi csoport eredménye megmarad.',
              ),
            ],
            if (error != null)
              banner(widget.sanitize?.call(error!) ?? error!, warning: true),
            for (final group in scopedGroups)
              if (widget.results.groups[group] != null &&
                  widget.clock().difference(
                        widget.results.groups[group]!.searchedAt,
                      ) >=
                      uncheckedAfter)
                banner(
                  '${deviceGroupLabels[group]}: Utoljára frissítve ${widget.clock().difference(widget.results.groups[group]!.searchedAt).inHours} órája – a tételek nem ellenőrzöttek',
                  action: TextButton(
                    onPressed: busy ? null : () => refreshGroups({group}),
                    child: const Text('Frissítés'),
                  ),
                ),
            if (runs.values.any((r) => r.status != 'success'))
              banner(
                'Részleges keresés – néhány lekérdezés nem sikerült. A részletek lent megnyithatók.',
                warning: true,
              ),
            if (tab != 'all' && widget.results.groups[tab] == null)
              banner('Ebben a csoportban még nem kerestél'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${listings.length} / $mainCount találat · $calls hívás · ${last == null ? 'Még nincs keresés' : dateLabel(last)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  width: width < 600 ? 155 : 235,
                  child: DropdownButton<ListingOrder>(
                    isExpanded: true,
                    value: filter(filterGroup).order,
                    items: ListingOrder.values
                        .map(
                          (order) => DropdownMenuItem(
                            value: order,
                            child: Text(
                              order.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        changeFilter(filterGroup, 'order', value!.name),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final group in scopedGroups)
                  for (final entry in filter(group).active.entries)
                    InputChip(
                      label: Text(
                        '${tab == 'all' ? '${deviceGroupLabels[group]} · ' : ''}${filterLabels[entry.key]}: ${chipValue(entry.key, entry.value)}',
                      ),
                      onDeleted: () {
                        changeFilter(
                          group,
                          entry.key,
                          GroupSearchFilter.defaults[entry.key],
                        );
                        setState(() => filterEpoch++);
                      },
                    ),
                if (scopedGroups.any(
                  (group) => filter(group).active.isNotEmpty,
                ))
                  TextButton(
                    onPressed: () {
                      for (final group in scopedGroups) {
                        clearFilter(group);
                      }
                    },
                    child: const Text('Szűrők törlése'),
                  ),
              ],
            ),
            ExpansionTile(
              key: PageStorageKey('search-details-$tab'),
              title: const Text('Keresés részletei'),
              children: [
                Text('Mai API-felhasználás: ${todayUsage ?? 'Nem ismert'}'),
                if (MoneyScope.displayOf(context).rate != null)
                  Text(MoneyScope.displayOf(context).rateLabel),
                for (final group in scopedGroups)
                  if ((failures[group] ?? widget.results.groups[group])
                      case final result?) ...[
                    Text(
                      '${deviceGroupLabels[group]} · ${statusLabel(result.status)} · ${result.apiCalls} hívás',
                    ),
                    for (final country in result.countries)
                      ExpansionTile(
                        key: PageStorageKey(
                          'country-$tab-$group-${country.country}',
                        ),
                        title: Text(
                          '${countryName(country.country)} · ${statusLabel(country.status)}',
                        ),
                        children: [
                          for (final query in country.queries)
                            ListTile(
                              title: Text(
                                '${query.query} · ${statusLabel(query.status)}',
                              ),
                              subtitle: Text(
                                '${query.error ?? '${query.count} találat'}${query.warnings.isEmpty ? '' : '\n${query.warnings.join('\n')}'}',
                              ),
                            ),
                        ],
                      ),
                  ],
              ],
            ),
            const SizedBox(height: 12),
            if (listings.isEmpty && runs.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'A jelenlegi szűrőkkel nincs megjeleníthető találat.',
                ),
              ),
          ] else ...[
            Row(
              children: [
                BackButton(onPressed: () => setState(() => hidden = null)),
                Expanded(
                  child: Text(
                    hidden!.title,
                    key: const ValueKey('hidden-group-heading'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            if (hiddenRows.where(hidden!.contains).isEmpty)
              const Text('Ebben a csoportban nincs megjeleníthető tétel.'),
          ],
        ];
        final rows = hidden == null
            ? listings
            : hiddenRows.where(hidden!.contains).toList();
        final columns = width >= 1050
            ? 3
            : width >= 680
            ? 2
            : 1;
        final known = hidden == null
            ? rows.where((item) => item.shipping != null).toList()
            : rows;
        final unknown = hidden == null
            ? rows.where((item) => item.shipping == null).toList()
            : <Listing>[];
        final knownRows = (known.length / columns).ceil();
        final unknownRows = (unknown.length / columns).ceil();
        final rowCount = knownRows + unknownRows + (unknown.isEmpty ? 0 : 1);
        return ListView.builder(
          key: PageStorageKey('$tab-${hidden?.name}'),
          padding: const EdgeInsets.all(20),
          itemCount: headers.length + rowCount + 1,
          itemBuilder: (context, index) {
            if (index < headers.length) return headers[index];
            if (index == headers.length + rowCount) {
              return hidden == null
                  ? ExpansionTile(
                      key: PageStorageKey('hidden-footer-$tab'),
                      title: Text('Rejtett tételek (${hiddenRows.length})'),
                      children: [
                        for (final group in HiddenGroup.values)
                          ListTile(
                            title: Text(group.title),
                            trailing: Text(
                              '${hiddenRows.where(group.contains).length}',
                            ),
                            onTap: () => setState(() => hidden = group),
                          ),
                      ],
                    )
                  : const SizedBox();
            }
            final position = index - headers.length;
            if (unknown.isNotEmpty && position == knownRows) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Ismeretlen szállítási díj – a hirdetésben ellenőrizd',
                ),
              );
            }
            final inKnown = position < knownRows;
            final offset =
                (inKnown ? position : position - knownRows - 1) * columns;
            return cardGrid(
              (inKnown ? known : unknown).skip(offset).take(columns).toList(),
              width,
            );
          },
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: const Text('Console Deal Finder'),
          actions: [
            if (widget.onSettings != null)
              IconButton(
                onPressed: widget.onSettings,
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Beállítások',
              ),
          ],
        ),
        bottomNavigationBar: widget.navigation,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, inner) => body(inner.maxWidth),
                  ),
                ),
                if (wide && showFilters)
                  SizedBox(
                    width: 350,
                    child: filterPanel(
                      () => setState(() => showFilters = false),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
