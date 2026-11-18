import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api/models.dart';
import 'currency.dart';
import 'group_results.dart';
import 'listing_card.dart';
import 'search_workspace.dart';
import 'sync.dart';
import 'watch_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.initial,
    this.initialGroups,
    this.saveGroups,
    this.loadConfig,
    required this.search,
    required this.loadDetails,
    this.saveResult,
    this.openSettings,
    this.settingsPage,
    this.shared,
    this.sanitize,
    this.watchNavigation,
    this.openWatchesInitially = false,
    this.clock = DateTime.now,
  });
  final SearchResult? initial;
  final GroupResults? initialGroups;
  final Future<void> Function(GroupResults)? saveGroups;
  final Future<PingResult> Function()? loadConfig;
  final Future<SearchResult> Function(Set<String> groups) search;
  final Future<ListingDetails> Function(String) loadDetails;
  final Future<void> Function(SearchResult)? saveResult;
  final VoidCallback? openSettings;
  final Widget Function(Widget? navigation)? settingsPage;
  final SharedState? shared;
  final String Function(String)? sanitize;
  final Listenable? watchNavigation;
  final bool openWatchesInitially;
  final DateTime Function() clock;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with WidgetsBindingObserver {
  late final GroupResults groups =
      widget.initialGroups ??
      (widget.initial == null
          ? GroupResults()
          : GroupResults.fromJson(widget.initial!.toCacheJson()));
  late SearchResult? result =
      widget.initial ?? groups.groups.values.firstOrNull;
  final updatedListings = <String, Listing>{};
  final unavailable = <String>{};
  int generation = 0;
  int section = 0;
  bool wideLayout = false;
  String localCurrency = 'EUR';
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.shared?.addListener(refresh);
    widget.watchNavigation?.addListener(openWatches);
    if (widget.openWatchesInitially) section = 2;
    scheduleRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    widget.shared?.removeListener(refresh);
    widget.watchNavigation?.removeListener(openWatches);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      unawaited(widget.shared?.sync());
    }
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shared != widget.shared) {
      oldWidget.shared?.removeListener(refresh);
      widget.shared?.addListener(refresh);
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void scheduleRefresh() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  void openWatches() {
    setState(() => section = 2);
    unawaited(widget.shared?.sync());
  }

  MoneyDisplay get priceDisplay => MoneyDisplay(
    widget.shared?.currency ?? localCurrency,
    widget.shared?.exchangeRate ?? result?.exchangeRate,
  );
  void toggleCurrency() {
    if (priceDisplay.rate == null) return;
    final next = priceDisplay.huf ? 'EUR' : 'HUF';
    if (widget.shared case final shared?) {
      unawaited(shared.setCurrency(next));
    } else {
      setState(() => localCurrency = next);
    }
  }

  Future<void> persistGroups(GroupResults next) async {
    result = next.groups.values.lastOrNull;
    if (widget.saveGroups != null) {
      await widget.saveGroups!(next);
    } else if (result != null) {
      await widget.saveResult?.call(result!);
    }
  }

  Future<ListingDetails> loadAndUpdateDetails(String id) async {
    final details = await widget.loadDetails(id);
    if (!mounted) return details;
    final original =
        groups.groups.values
            .expand((r) => r.allListings)
            .where((item) => item.id == id)
            .firstOrNull ??
        widget.shared?.favorites
            .where((f) => f.item.id == id)
            .firstOrNull
            ?.item;
    if (original != null) {
      setState(() => updatedListings[id] = details.update(original));
      groups.details(id, details);
      await persistGroups(groups);
    }
    return details;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      wideLayout = wide;
      final content = section == 4 && widget.settingsPage != null
          ? widget.settingsPage!(navigation())
          : section == 2 && widget.shared != null
          ? WatchScreen(
              shared: widget.shared!,
              now: widget.clock(),
              navigation: navigation(),
            )
          : section != 0 && widget.shared != null
          ? savedScreen(widget.clock())
          : SearchWorkspace(
              results: groups,
              search: widget.search,
              details: widget.loadDetails,
              clock: widget.clock,
              shared: widget.shared,
              config: widget.loadConfig,
              onSettings: widget.settingsPage != null
                  ? () => selectSection(4)
                  : widget.openSettings,
              sanitize: widget.sanitize,
              navigation: navigation(),
              persist: persistGroups,
              card: (item, now, loader, label) => listingCard(
                item,
                now,
                detailsLoader: loader,
                groupLabel: label,
              ),
            );
      return MoneyScope(
        display: priceDisplay,
        toggle: toggleCurrency,
        child: wide && widget.shared != null
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: section,
                    onDestinationSelected: selectSection,
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.search),
                        label: Text('Keresés'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.favorite_border),
                        label: Text('Kedvencek'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.notifications_outlined),
                        label: Text('Figyelés'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.visibility_off_outlined),
                        label: Text('Elrejtett'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        label: Text('Beállítások'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
      );
    },
  );

  Widget listingCard(
    Listing item,
    DateTime now, {
    Future<ListingDetails> Function(String)? detailsLoader,
    bool groupLabel = false,
  }) => ListingCard(
    key: ValueKey((generation, item.id)),
    showDeviceGroup: groupLabel,
    item: item,
    now: now,
    loadDetails: detailsLoader ?? loadAndUpdateDetails,
    unavailable: unavailable.contains(item.id),
    onUnavailable: () => setState(() => unavailable.add(item.id)),
    favorite: widget.shared?.isFavorite(item) ?? false,
    newLabel: widget.shared?.isNew(item) ?? item.isNew,
    onOpened: widget.shared == null
        ? null
        : () => widget.shared!.dismissNew(item),
    onFavorite: widget.shared == null
        ? null
        : () => unawaited(widget.shared!.toggleFavorite(item)),
    onHide: widget.shared == null ? null : () => hide(item),
    watchThreshold: widget.shared?.watchFor(item)?.threshold,
    onWatch: widget.shared == null || item.status != 'ACTIVE'
        ? null
        : () => watchAuction(item),
  );

  Future<void> watchAuction(Listing item) async {
    final shared = widget.shared!;
    final watch = shared.watchFor(item);
    final terms = await editWatchTerms(context, watch, currency: priceDisplay);
    if (terms == null || !mounted) return;
    if (watch == null) {
      await shared.addWatch(item, terms.threshold, terms.lead);
    } else {
      await shared.updateWatch(watch, terms.threshold, terms.lead);
    }
  }

  void hide(Listing item) {
    final shared = widget.shared!;
    unawaited(shared.hide(item));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Hirdetés elrejtve.'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Visszavonás',
            onPressed: () => unawaited(shared.unhide(item.toJson())),
          ),
        ),
      );
  }

  void selectSection(int value) {
    if (value == 4 && widget.settingsPage == null) {
      widget.openSettings?.call();
      return;
    }
    setState(() => section = value);
    if (value == 1) unawaited(widget.shared?.refresh());
    if (value == 2 || value == 3) unawaited(widget.shared?.sync());
  }

  Widget? navigation() {
    if (widget.shared == null || wideLayout) {
      return null;
    }
    return NavigationBar(
      selectedIndex: section,
      onDestinationSelected: selectSection,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.search), label: 'Keresés'),
        NavigationDestination(
          icon: Icon(Icons.favorite_border),
          label: 'Kedvencek',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_outlined),
          label: 'Figyelés',
        ),
        NavigationDestination(
          icon: Icon(Icons.visibility_off_outlined),
          label: 'Elrejtett',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          label: 'Beállítások',
        ),
      ],
    );
  }

  Widget savedScreen(DateTime now) {
    final shared = widget.shared!;
    final favorites = shared.favorites.toList()
      ..sort((a, b) {
        final endedA = favoriteStatus(a.item, now) == 'ENDED';
        final endedB = favoriteStatus(b.item, now) == 'ENDED';
        return endedA == endedB
            ? b.savedAt.compareTo(a.savedAt)
            : (endedA ? 1 : -1);
      });
    final hidden = shared.hidden.toList();
    return Scaffold(
      appBar: AppBar(title: Text(section == 1 ? 'Kedvencek' : 'Elrejtett')),
      bottomNavigationBar: navigation(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: section == 1
                  ? [
                      if (favorites.isEmpty)
                        const Text('Még nincsenek kedvencek.'),
                      for (final favorite in favorites)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ListingCard(
                            key: ValueKey(listingKey(favorite.item)),
                            item:
                                updatedListings[favorite.item.id] ??
                                favorite.item,
                            now: now,
                            favorite: true,
                            watchThreshold: shared
                                .watchFor(favorite.item)
                                ?.threshold,
                            onWatch:
                                favoriteStatus(favorite.item, now) == 'ACTIVE'
                                ? () => watchAuction(favorite.item)
                                : null,
                            savedStatus: favoriteStatus(favorite.item, now),
                            onFavorite: () =>
                                unawaited(shared.toggleFavorite(favorite.item)),
                            onHide: shared.isHidden(favorite.item)
                                ? null
                                : () => hide(favorite.item),
                            loadDetails: loadAndUpdateDetails,
                            unavailable: unavailable.contains(favorite.item.id),
                            onUnavailable: () => setState(
                              () => unavailable.add(favorite.item.id),
                            ),
                          ),
                        ),
                    ]
                  : [
                      if (hidden.isEmpty)
                        const Text('Még nincsenek elrejtett hirdetések.'),
                      for (final row in hidden)
                        ListTile(
                          title: Text(row['title'] as String),
                          trailing: TextButton(
                            onPressed: () => unawaited(shared.unhide(row)),
                            child: const Text('Visszaállítás'),
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
