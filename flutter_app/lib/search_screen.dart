import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'listing_card.dart';
import 'listings.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.initial,
    required this.search,
    required this.loadDetails,
    this.saveResult,
    this.openSettings,
    this.sanitize,
    this.clock = DateTime.now,
  });
  final SearchResult? initial;
  final Future<SearchResult> Function() search;
  final Future<ListingDetails> Function(String) loadDetails;
  final Future<void> Function(SearchResult)? saveResult;
  final VoidCallback? openSettings;
  final String Function(String)? sanitize;
  final DateTime Function() clock;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with WidgetsBindingObserver {
  final title = TextEditingController();
  final price = TextEditingController();
  final total = TextEditingController();
  final models = <String>{};
  final unavailable = <String>{};
  late SearchResult? result = widget.initial;
  late bool cached = widget.initial != null;
  BuyingFilter buying = BuyingFilter.both;
  ListingOrder order = ListingOrder.total;
  HiddenGroup? selectedGroup;
  String? country;
  bool ending = false, boards = false, busy = false;
  String? error, cacheError;
  Timer? timer;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    title.dispose();
    price.dispose();
    total.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  void refresh() {
    if (!mounted) return;
    setState(() {});
    scheduleRefresh();
  }

  void scheduleRefresh() {
    timer?.cancel();
    final now = widget.clock();
    Duration? next;
    void scheduleAt(DateTime time) {
      final duration = time.difference(now);
      if (duration > Duration.zero && (next == null || duration < next!)) {
        next = duration;
      }
    }

    for (final item in result?.allListings ?? const <Listing>[]) {
      if (!visibleListing(item, now)) continue;
      scheduleAt(item.checkedAt.add(uncheckedAfter));
      scheduleAt(item.checkedAt.add(maxListingAge));
      if (item.auction) {
        scheduleAt(item.end!);
        scheduleAt(item.end!.subtract(day));
        scheduleAt(item.end!.subtract(day * 2));
        if (!isUnchecked(item, now)) {
          scheduleAt(now.add(const Duration(seconds: 1)));
        }
      }
    }
    if (next != null) timer = Timer(next!, refresh);
  }

  Future<void> runSearch() async {
    setState(() {
      busy = true;
      error = null;
      cacheError = null;
    });
    try {
      final searched = await widget.search();
      if (!mounted) return;
      if (searched.status == 'success') {
        try {
          await widget.saveResult?.call(searched);
        } on Exception {
          cacheError = 'Az eredmény offline mentése nem sikerült.';
        }
      }
      if (!mounted) return;
      setState(() {
        result = searched;
        generation++;
        unavailable.clear();
        cached = false;
      });
      scheduleRefresh();
    } on AppFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  double? limit(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value >= 0 ? value : null;
  }

  String? amountError(TextEditingController controller) =>
      controller.text.trim().isNotEmpty && limit(controller) == null
      ? 'Adj meg egy pozitív számot vagy nullát.'
      : null;

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final data = result;
    final active =
        data?.allListings.where((item) => visibleListing(item, now)).toList() ??
        <Listing>[];
    if (selectedGroup case final group?) {
      return hiddenResults(group, active.where(group.contains).toList(), now);
    }
    final visible = selectListings(
      active,
      ListingFilters(
        models: models,
        maxPrice: limit(price),
        maxTotal: limit(total),
        buying: buying,
        endingSoon: ending,
        mainboards: boards,
        title: title.text,
        country: country,
      ),
      order,
      now,
    );
    final known = visible
        .where((item) => !inUnknownShippingBlock(item))
        .toList();
    final unknown = visible.where(inUnknownShippingBlock).toList();
    return Scaffold(
      appBar: AppBar(
        leading: Icon(
          Icons.sports_esports_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Console Deal Finder'),
        actions: [
          if (widget.openSettings != null)
            IconButton(
              onPressed: widget.openSettings,
              tooltip: 'Beállítások',
              icon: const Icon(Icons.settings_outlined),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 1080
                ? 3
                : box.maxWidth >= 720
                ? 2
                : 1;
            final gutter = box.maxWidth >= 600 ? 28.0 : 16.0;
            final inset =
                ((box.maxWidth - 1320) / 2).clamp(0.0, double.infinity) +
                gutter;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 16, inset, 14),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Keresés',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),
                        filters(active),
                        if (busy)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(),
                                SizedBox(height: 8),
                                Text('Keresés folyamatban… kb. 10 másodperc'),
                              ],
                            ),
                          ),
                        if (error != null)
                          notice('A keresés sikertelen. $error', warning: true),
                        if (cacheError != null)
                          notice(cacheError!, warning: true),
                        if (data != null) ...[
                          if (cached)
                            notice(
                              'Korábban mentett eredmény – utoljára frissítve: ${dateLabel(data.searchedAt)}',
                            ),
                          if (data.status == 'partial')
                            notice(
                              'Részleges keresés – egyes országok vagy lekérdezések sikertelenek.',
                              warning: true,
                            ),
                          if (data.status == 'error')
                            notice(
                              'A keresés sikertelen – egyetlen lekérdezés sem sikerült.',
                              warning: true,
                            ),
                          summary(data, visible.length, active),
                          if (data.status != 'error' && visible.isEmpty)
                            notice(
                              'Nincs megjeleníthető találat az aktuális szűrőkkel.',
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                ...resultRows(known, columns, inset, now),
                if (unknown.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 14, inset, 10),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Ismeretlen szállítási díj – a hirdetésben ellenőrizd',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                ...resultRows(unknown, columns, inset, now),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget filters(List<Listing> active) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Konzolmodell', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final model in consoleModels)
                FilterChip(
                  label: Text(model),
                  selected: models.contains(model),
                  onSelected: (selected) => setState(
                    () => selected ? models.add(model) : models.remove(model),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth >= 820
                  ? (box.maxWidth - 36) / 4
                  : box.maxWidth >= 440
                  ? (box.maxWidth - 12) / 2
                  : box.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: priceField(price, 'Max. vételár'),
                  ),
                  SizedBox(
                    width: width,
                    child: priceField(total, 'Max. teljes ár'),
                  ),
                  SizedBox(
                    width: width,
                    child: dropdown('Hirdetéstípus', buying, {
                      for (final option in BuyingFilter.values)
                        option: option.label,
                    }, (value) => setState(() => buying = value)),
                  ),
                  SizedBox(
                    width: width,
                    child: dropdown('Aukciók', ending, {
                      false: 'Mind',
                      true: '24 órán belül záródók',
                    }, (value) => setState(() => ending = value)),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Alaplapok mutatása',
                    child: Switch(
                      value: boards,
                      onChanged: (value) => setState(() => boards = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Alaplapok mutatása'),
                ],
              ),
              FilledButton.icon(
                onPressed: busy ? null : runSearch,
                icon: const Icon(Icons.search),
                label: const Text('Keresés indítása'),
              ),
            ],
          ),
          if (result != null) ...[
            const Divider(height: 28),
            LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth >= 700
                    ? (box.maxWidth - 24) / 3
                    : box.maxWidth;
                final available =
                    active
                        .map((item) => item.country)
                        .whereType<String>()
                        .toSet()
                        .toList()
                      ..sort(
                        (a, b) => countryName(a).compareTo(countryName(b)),
                      );
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: TextField(
                        controller: title,
                        decoration: const InputDecoration(
                          labelText: 'Keresés a címekben',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: dropdown('Rendezés', order, {
                        for (final option in ListingOrder.values)
                          option: option.label,
                      }, (value) => setState(() => order = value)),
                    ),
                    SizedBox(
                      width: width,
                      child: dropdown(
                        'Ország',
                        country ?? '',
                        {
                          '': 'Mind',
                          for (final code in {...available, ?country})
                            code: countryName(code),
                        },
                        (value) => setState(
                          () => country = value.isEmpty ? null : value,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    ),
  );

  Widget priceField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'EUR',
          errorText: amountError(controller),
        ),
        onChanged: (_) => setState(() {}),
      );

  Widget dropdown<T>(
    String label,
    T current,
    Map<T, String> options,
    ValueChanged<T> change,
  ) => DropdownButtonFormField<T>(
    initialValue: current,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final entry in options.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) {
      if (value != null) change(value);
    },
  );

  Widget notice(String message, {bool warning = false}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: warning ? colors.errorContainer : colors.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  warning ? Icons.warning_amber : Icons.info_outline,
                  size: 20,
                  color: warning
                      ? colors.onErrorContainer
                      : colors.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: warning
                          ? colors.onErrorContainer
                          : colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String safeText(String text) => widget.sanitize?.call(text) ?? text;

  Widget hiddenResults(HiddenGroup group, List<Listing> items, DateTime now) {
    void back() => setState(() => selectedGroup = null);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: back),
          title: Text(group.title),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 1080
                  ? 3
                  : box.maxWidth >= 720
                  ? 2
                  : 1;
              final inset =
                  ((box.maxWidth - 1320) / 2).clamp(0.0, double.infinity) +
                  (box.maxWidth >= 600 ? 28.0 : 16.0);
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 16, inset, 14),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        items.isEmpty
                            ? 'Ebben a csoportban nincs megjeleníthető tétel.'
                            : '${items.length} tétel',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  ...resultRows(items, columns, inset, now),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget summary(SearchResult data, int count, List<Listing> active) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.status != 'error')
            Text(
              '$count / ${active.length} találat',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                'API-hívások: ${data.apiCalls} futásban · ${data.dailyApiCalls} ${cached ? 'akkor aznap' : 'ma'}',
              ),
              Text('Keresés: ${dateLabel(data.searchedAt)}'),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final group in HiddenGroup.values)
                TextButton(
                  onPressed: () => setState(() => selectedGroup = group),
                  child: Text(
                    '${active.where(group.contains).length} · ${group.title}',
                  ),
                ),
              Text(
                '${data.filteredNonEu} EU-n kívüli vagy ismeretlen helyű tétel kiszűrve',
              ),
            ],
          ),
          if (data.quotaWarning case final warning?)
            notice(safeText(warning), warning: true),
          if (data.countries.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Országonkénti állapot és figyelmeztetések'),
              children: [
                for (final country in data.countries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${countryName(country.country)} · ${switch (country.status) {
                        'success' => 'Sikeres',
                        'partial' => 'Részleges',
                        _ => 'Hiba',
                      }}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final query in country.queries) ...[
                          Text(
                            '${query.query}: ${query.status == 'success' ? '${query.count} találat' : 'Hiba'}',
                          ),
                          if (query.error case final error?)
                            Text('Hiba: ${safeText(error)}'),
                          for (final warning in query.warnings)
                            Text(
                              'Figyelmeztetés: ${safeText(warning is Json && warning['message'] is String
                                  ? warning['message'] as String
                                  : warning is String
                                  ? warning
                                  : 'eBay figyelmeztetés')}',
                            ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  Iterable<Widget> resultRows(
    List<Listing> items,
    int columns,
    double inset,
    DateTime now,
  ) sync* {
    if (items.isEmpty) return;
    yield SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      sliver: SliverList.builder(
        itemCount: (items.length + columns - 1) ~/ columns,
        itemBuilder: (context, row) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 14),
                Expanded(
                  child: row * columns + column < items.length
                      ? listingCard(items[row * columns + column], now)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget listingCard(Listing item, DateTime now) => ListingCard(
    key: ValueKey((generation, item.id)),
    item: item,
    now: now,
    loadDetails: widget.loadDetails,
    unavailable: unavailable.contains(item.id),
    onUnavailable: () => setState(() => unavailable.add(item.id)),
  );
}
