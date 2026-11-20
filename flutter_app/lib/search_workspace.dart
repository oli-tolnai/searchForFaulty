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
import 'app_theme.dart';

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
  String titleQuery = '';
  int runGeneration = 0;
  Map<String, SearchResult>? previousDisplay;
  Map<String, SearchResult> get displayed => busy && previousDisplay != null
      ? previousDisplay!
      : widget.results.groups;
  bool requestInFlight = false;
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

  Widget filterPanel(VoidCallback close) => StatefulBuilder(
    builder: (context, rebuild) {
      final group = filterGroup;
      return Column(
        children: [
          if (tab == 'all')
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String>(
                key: ValueKey('filter-group-$group'),
                initialValue: group,
                decoration: const InputDecoration(
                  labelText: 'Kategória szűrői',
                ),
                items: [
                  for (final key in visibleGroups)
                    DropdownMenuItem(value: key, child: Text(label(key))),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => filterGroup = value);
                    rebuild(() {});
                  }
                },
              ),
            ),
          Expanded(
            child: SearchFilterPanel(
              key: ValueKey('$group-$filterEpoch'),
              group: group,
              read: () => filter(group),
              change: (key, value) => changeFilter(group, key, value),
              close: close,
              clear: () => clearFilter(group),
              count: () =>
                  shown.where((item) => item.deviceGroup == group).length,
              alert: widget.shared == null ? null : createAlert,
              desktop: MediaQuery.sizeOf(context).width >= Ui.desktop,
            ),
          ),
        ],
      );
    },
  );

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
      for (final item in displayed[group]?.allListings ?? <Listing>[]) {
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
        .where(
          (item) =>
              filter(item.deviceGroup).matches(item, now) &&
              item.title.toLowerCase().contains(titleQuery.toLowerCase()),
        )
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
    if (busy || requestInFlight || confirming || groups.isEmpty) return;
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
    final generation = ++runGeneration;
    previousDisplay = Map.of(widget.results.groups);
    requestInFlight = true;
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
          if (!mounted || generation != runGeneration) return;
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
      requestInFlight = false;
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
  String label(String group) => group == 'all' ? 'Összes' : tabLabel(group);
  String updated(DateTime value) {
    final local = value.toLocal(), today = widget.clock().toLocal();
    return local.year == today.year &&
            local.month == today.month &&
            local.day == today.day
        ? time(value)
        : dateLabel(value);
  }

  Future<void> hiddenMenu(List<Listing> items) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Rejtett tételek (${items.length})'),
      content: SizedBox(
        width: 440,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final group in HiddenGroup.values)
              if (items.any(group.contains))
                ListTile(
                  title: Text(group.title),
                  trailing: Text('${items.where(group.contains).length}'),
                  onTap: () {
                    Navigator.pop(dialog);
                    setState(() => hidden = group);
                  },
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Bezárás'),
        ),
      ],
    ),
  );
  String time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
  List<Listing> activeFor(Iterable<String> groups) => groups
      .expand((group) => displayed[group]?.allListings ?? <Listing>[])
      .where(
        (item) =>
            visibleListing(item, widget.clock()) &&
            widget.shared?.isHidden(item) != true &&
            filter(item.deviceGroup).allowsType(item),
      )
      .toList();
  void choose(String group) => setState(() {
    tab = group;
    hidden = null;
    if (group != 'all') filterGroup = group;
  });
  Future<void> categories() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheet).height * .9,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Mit keresel?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final group in ['all', ...visibleGroups])
            ListTile(
              key: ValueKey('category-$group'),
              minTileHeight: 64,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              selected: tab == group,
              selectedTileColor: Ui.selected,
              leading: Icon(groupIcons[group]),
              title: Text(group == 'all' ? 'Összes kategória' : label(group)),
              subtitle: Text(
                group == 'all'
                    ? 'A megtartott találatok együtt'
                    : widget.results.groups[group] == null
                    ? 'Még nem kerestél'
                    : 'Frissítve ${updated(widget.results.groups[group]!.searchedAt)}${widget.clock().difference(widget.results.groups[group]!.searchedAt) >= uncheckedAfter ? ' · nem ellenőrzött' : ''}',
              ),
              trailing: Text(
                '${activeFor(group == 'all' ? visibleGroups : [group]).length}',
              ),
              onTap: () {
                choose(group);
                Navigator.pop(sheet);
              },
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(sheet);
              visibleCategories();
            },
            child: const Text('Kategóriák megjelenítése…'),
          ),
        ],
      ),
    ),
  );
  Future<void> visibleCategories() => showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Kategóriák megjelenítése'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final group in deviceGroups)
                CheckboxListTile(
                  title: Text(label(group)),
                  value: visibleGroups.contains(group),
                  onChanged: widget.shared == null
                      ? null
                      : (value) async {
                          final next = visibleGroups.toSet();
                          if (value == true) {
                            next.add(group);
                          } else if (next.length > 1) {
                            next.remove(group);
                          }
                          await widget.shared!.setVisibleSearchGroups(
                            next.toList(),
                          );
                          update(() {});
                        },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Kész'),
          ),
        ],
      ),
    ),
  );
  Widget currencySwitch() => OutlinedButton(
    onPressed: MoneyScope.displayOf(context).rate == null
        ? null
        : MoneyScope.maybeOf(context)?.toggle,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: const Text('EUR · Ft'),
  );
  Widget categoryHeader(bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(
      wide ? 24 : 16,
      wide ? 20 : 12,
      wide ? 24 : 16,
      8,
    ),
    child: Row(
      children: [
        Expanded(
          child: wide
              ? Text(
                  'Keresés',
                  style: Theme.of(context).textTheme.headlineSmall,
                )
              : Semantics(
                  button: true,
                  label: 'Kategória választása',
                  child: InkWell(
                    key: const ValueKey('category-picker'),
                    onTap: categories,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              label(tab),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Ui.surface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${activeFor(scopedGroups).length}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const Icon(Icons.expand_more, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        currencySwitch(),
      ],
    ),
  );
  Widget desktopTabs() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    child: Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final group in ['all', ...visibleGroups])
          ChoiceChip(
            label: Text(label(group)),
            selected: tab == group,
            onSelected: (_) => choose(group),
          ),
      ],
    ),
  );
  Widget searchField() => TextField(
    key: const ValueKey('title-search'),
    decoration: const InputDecoration(
      hintText: 'Keresés a címekben',
      prefixIcon: Icon(Icons.search),
      constraints: BoxConstraints(minHeight: 44),
    ),
    onChanged: (value) => setState(() => titleQuery = value),
  );
  Widget sortButton() => SizedBox(
    width: 180,
    child: PopupMenuButton<ListingOrder>(
      tooltip: 'Rendezés',
      initialValue: filter(filterGroup).order,
      onSelected: (value) => changeFilter(filterGroup, 'order', value.name),
      itemBuilder: (_) => [
        for (final order in ListingOrder.values)
          PopupMenuItem(value: order, child: Text(order.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                filter(filterGroup).order.label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Set<String> get requestedGroups =>
      tab == 'all' ? selected.where(visibleGroups.contains).toSet() : {tab};
  Widget searchButton({
    bool wide = false,
    bool initial = false,
  }) => FilledButton.icon(
    key: const ValueKey('run-search'),
    onPressed: busy || requestInFlight
        ? null
        : () => refreshGroups(requestedGroups),
    icon: const Icon(Icons.refresh, size: 16),
    label: Text(
      initial
          ? 'Keresés indítása'
          : wide
          ? 'Keresés · ${estimate(requestedGroups) == null ? 'becslés nincs' : 'kb. ${estimate(requestedGroups)} hívás'}'
          : 'Keresés',
    ),
  );
  Widget activeChips() => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final group in scopedGroups)
        for (final entry in filter(group).active.entries)
          InputChip(
            deleteButtonTooltipMessage: 'Feltétel eltávolítása',
            label: Text(
              '${tab == 'all' ? '${label(group)} · ' : ''}${filterLabels[entry.key] ?? entry.key}: ${chipValue(entry.key, entry.value)}',
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
      if (scopedGroups.any((group) => filter(group).active.isNotEmpty))
        TextButton(
          onPressed: () {
            for (final group in scopedGroups) {
              clearFilter(group);
            }
          },
          child: const Text('Szűrők törlése'),
        ),
    ],
  );
  Widget empty(bool wide) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 16),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Ui.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(groupIcons[tab], size: 40, color: Ui.primary),
        ),
        const SizedBox(height: 24),
        Text(
          'Ebben a csoportban még nem kerestél',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          '${label(tab)} keresése az EU országaiban, Magyarországra szállítással.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        searchButton(initial: true),
        const SizedBox(height: 12),
        Text(
          'kb. ${estimate(requestedGroups) ?? 'Nem ismert'} eBay-hívás · ma ${todayUsage ?? 'Nem ismert'} / 5000 felhasználva',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          onPressed: () => openFilters(wide),
          child: const Text('Előbb beállítom a szűrőket'),
        ),
      ],
    ),
  );
  Widget progress() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Keresés folyamatban…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  runGeneration++;
                  busy = false;
                  error = 'A keresés megszakítva. A már elküldött szerverkérés még befejeződhet.';
                }),
                child: const Text('Mégse'),
              ),
            ],
          ),
          const LinearProgressIndicator(),
          const SizedBox(height: 10),
          const Text(
            'Az országok eredményei együtt érkeznek. A korábbi találatok a keresés végéig látszanak.',
          ),
        ],
      ),
    ),
  );
  Widget skeleton() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Ui.border,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (final fraction in [.9, .7, .5])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FractionallySizedBox(
                        widthFactor: fraction,
                        child: Container(height: 12, color: Ui.border),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget runDetails(Map<String, SearchResult> runs) => ExpansionTile(
    key: PageStorageKey('search-details-$tab'),
    title: const Text('Keresés részletei'),
    children: [
      Text('Mai API-felhasználás: ${todayUsage ?? 'Nem ismert'}'),
      if (MoneyScope.displayOf(context).rate != null)
        Text(MoneyScope.displayOf(context).rateLabel),
      if (tab == 'all')
        Wrap(
          spacing: 6,
          children: [
            for (final group in visibleGroups)
              FilterChip(
                label: Text(label(group)),
                selected: selected.contains(group),
                onSelected: (value) {
                  if (!value && selected.length == 1) return;
                  setState(
                    () => value ? selected.add(group) : selected.remove(group),
                  );
                  unawaited(
                    widget.shared?.setSelectedSearchGroups(selected.toList()),
                  );
                },
              ),
          ],
        ),
      if (tab == 'all')
        DropdownButton<String>(
          value: filterGroup,
          items: [
            for (final group in visibleGroups)
              DropdownMenuItem(
                value: group,
                child: Text('${label(group)} szűrői'),
              ),
          ],
          onChanged: (value) => setState(() => filterGroup = value!),
        ),
      for (final group in scopedGroups)
        if ((failures[group] ?? runs[group]) case final result?) ...[
          Text(
            '${label(group)} · ${statusLabel(result.status)} · ${result.apiCalls} hívás',
          ),
          for (final country in result.countries)
            ExpansionTile(
              key: PageStorageKey('country-$tab-$group-${country.country}'),
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
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final listings = shown;
      final runs = {
        for (final group in scopedGroups)
          if (displayed[group] != null) group: displayed[group]!,
      };
      final last = runs.isEmpty
          ? null
          : runs.values
                .map((r) => r.searchedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);
      final hiddenRows = active
          .where((item) => !filter(item.deviceGroup).allowsType(item))
          .toList();
      final mainCount = active
          .where((item) => filter(item.deviceGroup).allowsType(item))
          .length;
      final unsearched = runs.isEmpty;
      Widget hiddenFooter() => ExpansionTile(
        key: PageStorageKey('hidden-footer-$tab'),
        title: Text('Rejtett tételek (${hiddenRows.length})'),
        children: [
          for (final group in HiddenGroup.values)
            if (hiddenRows.any(group.contains))
              ListTile(
                title: Text(group.title),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${hiddenRows.where(group.contains).length}'),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => setState(() => hidden = group),
              ),
        ],
      );
      Widget body(double width) {
        final columns = wide
            ? (width >= 900
                  ? 4
                  : width >= 650
                  ? 3
                  : 2)
            : 1;
        final rows = hidden == null
            ? listings
            : hiddenRows.where(hidden!.contains).toList();
        final known = hidden == null
            ? rows.where((i) => i.shipping != null).toList()
            : rows;
        final unknown = hidden == null
            ? rows.where((i) => i.shipping == null).toList()
            : <Listing>[];
        final headers = <Widget>[
          if (hidden == null) ...[
            if (!unsearched) ...[
              Row(
                children: [
                  Expanded(child: searchField()),
                  const SizedBox(width: 8),
                  if (wide) ...[
                    sortButton(),
                    const SizedBox(width: 8),
                    searchButton(wide: true),
                  ] else
                    OutlinedButton.icon(
                      onPressed: () => openFilters(false),
                      icon: const Icon(Icons.tune, size: 18),
                      label: Text(
                        'Szűrők${filter(filterGroup).active.isEmpty ? '' : ' (${filter(filterGroup).active.length})'}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              activeChips(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${listings.length} találat · frissítve ${last == null ? '–' : time(last)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (wide)
                    TextButton(
                      onPressed: () => hiddenMenu(hiddenRows),
                      child: Text('Rejtett tételek (${hiddenRows.length})'),
                    )
                  else
                    searchButton(),
                ],
              ),
            ],
            if (busy) ...[progress(), const SizedBox(height: 12)],
            if (error != null)
              banner(widget.sanitize?.call(error!) ?? error!, warning: true),
            for (final group in scopedGroups)
              if (widget.results.groups[group] != null &&
                  widget.clock().difference(
                        widget.results.groups[group]!.searchedAt,
                      ) >=
                      uncheckedAfter)
                banner(
                  '${label(group)}: ${widget.clock().difference(widget.results.groups[group]!.searchedAt).inHours} órája frissítve – az árak és állapotok nem ellenőrzöttek.',
                  warning: true,
                  action: TextButton(
                    onPressed: busy ? null : () => refreshGroups({group}),
                    child: const Text('Frissítés'),
                  ),
                ),
            if (runs.values.any((r) => r.status != 'success'))
              banner(
                'Részleges keresés – néhány lekérdezés nem sikerült.',
                warning: true,
              ),
            if (unsearched && !busy) empty(wide),
            if (busy && unsearched)
              for (var i = 0; i < 3; i++) skeleton(),
            if (listings.isEmpty && !unsearched && !busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'A jelenlegi szűrőkkel nincs megjeleníthető találat.',
                ),
              ),
            if (scopedGroups.any(cachedGroups.contains) && !unsearched)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Korábban mentett eredmény · $mainCount alaplistás tétel',
                  style: Theme.of(context).textTheme.bodySmall,
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
            const SizedBox(height: 12),
          ],
        ];
        final knownRows = (known.length / columns).ceil(),
            unknownRows = (unknown.length / columns).ceil();
        final count = knownRows + unknownRows + (unknown.isEmpty ? 0 : 1);
        return ListView.builder(
          key: PageStorageKey('$tab-${hidden?.name}'),
          padding: EdgeInsets.all(wide ? 0 : 16),
          itemCount: headers.length + count + 1,
          itemBuilder: (context, index) {
            if (index < headers.length) return headers[index];
            if (index == headers.length + count) {
              return hidden == null
                  ? Column(
                      children: [
                        hiddenFooter(),
                        if (!unsearched) ...[
                          if (!wide)
                            Align(
                              alignment: Alignment.centerRight,
                              child: sortButton(),
                            ),
                          runDetails(runs),
                        ],
                      ],
                    )
                  : const SizedBox();
            }
            final row = index - headers.length;
            if (unknown.isNotEmpty && row == knownRows) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Ismeretlen szállítási díj – a hirdetésben ellenőrizd',
                ),
              );
            }
            final inKnown = row < knownRows;
            final offset = (inKnown ? row : row - knownRows - 1) * columns;
            final items = (inKnown ? known : unknown)
                .skip(offset)
                .take(columns)
                .toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Expanded(
                      child: i < items.length
                          ? widget.card(
                              items[i],
                              widget.clock(),
                              details,
                              tab == 'all',
                            )
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      }

      return Scaffold(
        bottomNavigationBar: widget.navigation,
        body: SafeArea(
          child: Column(
            children: [
              categoryHeader(wide),
              if (wide) desktopTabs(),
              Expanded(
                child: wide
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 272, child: filterPanel(() {})),
                            const SizedBox(width: 24),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, inner) =>
                                    body(inner.maxWidth),
                              ),
                            ),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, inner) => body(inner.maxWidth),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
