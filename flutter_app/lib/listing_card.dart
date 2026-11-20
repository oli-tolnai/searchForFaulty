import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'currency.dart';
import 'listings.dart';
import 'app_theme.dart';

import 'dart:async';

Uri translationLink(String text) => Uri.https('translate.google.com', '/', {
  'sl': 'auto',
  'tl': 'hu',
  'op': 'translate',
  'text': String.fromCharCodes(text.runes.take(4500)),
});

Future<void> openExternal(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } on Exception {
    // The platform error can include the complete URL.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('A böngésző nem tudta megnyitni a linket.')),
    );
  }
}

class ListingCard extends StatefulWidget {
  const ListingCard({
    super.key,
    required this.item,
    required this.now,
    required this.loadDetails,
    required this.onUnavailable,
    this.unavailable = false,
    this.favorite = false,
    this.onFavorite,
    this.onHide,
    this.onWatch,
    this.watchThreshold,
    this.watchValue,
    this.onOpened,
    this.newLabel = false,
    this.showDeviceGroup = false,
    this.savedStatus,
    this.detailed = false,
  });
  final Listing item;
  final DateTime now;
  final Future<ListingDetails> Function(String id) loadDetails;
  final VoidCallback onUnavailable;
  final bool unavailable, favorite, newLabel, showDeviceGroup;
  final bool detailed;
  final VoidCallback? onFavorite, onHide, onWatch, onOpened;
  final num? watchThreshold;
  final num? Function()? watchValue;

  final String? savedStatus;
  @override
  State<ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends State<ListingCard> {
  final revision = ValueNotifier(0);
  bool expanded = false, loading = false, routeOpen = false;
  bool? favoriteOverride;
  ListingDetails? details;
  String? error;
  Timer? ticker;
  Listing get item => details?.update(widget.item) ?? widget.item;
  DateTime get now => widget.now.add(
    routeOpen
        ? DateTime.now().difference(openedAt ?? DateTime.now())
        : Duration.zero,
  );
  DateTime? openedAt;
  bool get favorite => favoriteOverride ?? widget.favorite;
  void changed() {
    if (mounted) {
      setState(() {});
      revision.value++;
    }
  }

  @override
  void didUpdateWidget(covariant ListingCard old) {
    super.didUpdateWidget(old);
    if (old.favorite != widget.favorite) favoriteOverride = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && routeOpen) revision.value++;
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    revision.dispose();
    super.dispose();
  }

  Future<void> fetchDescription() async {
    expanded = !expanded;
    changed();
    if (!expanded || loading || details != null || widget.unavailable) return;
    loading = true;
    error = null;
    changed();
    try {
      details = await widget.loadDetails(widget.item.id);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      error = failure.message;
      if (failure.code == 'listing_not_found') widget.onUnavailable();
    } finally {
      loading = false;
      changed();
    }
  }

  void toggleFavorite() {
    favoriteOverride = !favorite;
    widget.onFavorite?.call();
    changed();
  }

  Widget image(double height, {double? width}) => SizedBox(
    height: height,
    width: width,
    child: item.image == null || now.difference(item.checkedAt) >= maxListingAge
        ? const ColoredBox(
            color: Ui.image,
            child: Center(
              child: Icon(Icons.image_outlined, color: Ui.muted, size: 28),
            ),
          )
        : Image.network(
            item.image.toString(),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Ui.image,
              child: Center(child: Icon(Icons.image_outlined, color: Ui.muted)),
            ),
          ),
  );
  Widget badge(
    String text, {
    Color foreground = Ui.muted,
    Color background = Ui.border,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
    ),
  );
  List<Widget> badges({bool full = false}) {
    final stale = isUnchecked(item, now);
    final remaining = item.end?.difference(now);
    final values = <Widget>[
      badge(
        item.auction
            ? '${item.options.contains('FIXED_PRICE') ? 'Aukció + Azonnali vétel' : 'Aukció'}${remaining != null && !stale ? ' · ${countdown(remaining)}' : ''}'
            : item.options.contains('FIXED_PRICE')
            ? 'Fix ár'
            : 'Hirdetéstípus: Nem ismert',
        foreground: item.auction ? Ui.auction : Ui.fixed,
        background: item.auction ? Ui.auctionSurface : Ui.fixedSurface,
      ),
      if (widget.newLabel && !stale && widget.savedStatus != 'ENDED')
        badge('ÚJ', foreground: Ui.primary, background: Ui.selected),
      if (widget.savedStatus == 'ENDED') badge('Lejárt / nem elérhető'),
      if (stale || widget.savedStatus == 'UNKNOWN') badge('Nem ellenőrzött'),
      if (widget.unavailable)
        badge('Valószínűleg lezárult', foreground: Ui.danger),
      if (full) ...[
        if (widget.showDeviceGroup) badge(deviceGroupLabels[item.deviceGroup]!),
        if (item.auction && remaining != null && remaining > day * 2 && !stale)
          badge(
            'Korai licit – a végső ár várhatóan magasabb',
            foreground: Ui.auction,
          ),
        if (item.type.endsWith('_bundle')) badge('Csomag'),
        if (item.type == 'needs_review') badge('Ellenőrzendő'),
        if (item.type == 'mainboard') badge('Alaplap'),
        if (item.isScuf) badge('Scuf'),
        if (item.model == 'DualSense (Egyedi)') badge('Egyedi'),
        if (item.model.contains('nem ismert'))
          badge('Generáció / változat nem ismert'),
        for (final group in HiddenGroup.values)
          if (group.contains(item)) badge(group.title),
        if (item.deviceGroup == 'iphone')
          badge(
            item.icloudStatus == 'free_by_seller'
                ? 'iCloud-mentes (az eladó szerint)'
                : item.icloudStatus == 'locked'
                ? 'iCloud-zárolt (csak alkatrésznek)'
                : 'Az iCloud-zár állapota nem ismert – vásárlás előtt kérdezd meg az eladót',
            foreground: Ui.auction,
          ),
        if (item.banned) badge('Tiltott (banned)', foreground: Ui.danger),
        if (item.possiblyNotFaulty) badge('Lehet, hogy nem hibás'),
        if (item.faultSource == 'title')
          badge('Használtként hirdetve – a hiba a címből derül ki'),
        if (item.faultSource == 'text')
          badge('A hiba a címből vagy a leírásból derül ki.'),
        if ((widget.watchValue?.call() ?? widget.watchThreshold) != null)
          badge(
            'Figyelve · ${MoneyScope.displayOf(context).format((widget.watchValue?.call() ?? widget.watchThreshold).toString(), 'EUR')}',
          ),
      ],
    ];
    return full ? values : values.take(2).toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.detailed) {
      openedAt = DateTime.now();
      routeOpen = true;
      ticker = Timer.periodic(const Duration(seconds: 1), (_) => changed());
    }
  }

  Future<void> openDetails() async {
    final money = MoneyScope.maybeOf(context);
    final openedNow = widget.now;
    var display = MoneyScope.displayOf(context);
    Widget view(BuildContext page) => StatefulBuilder(
      builder: (page, setPage) => MoneyScope(
        display: display,
        toggle: money?.toggle == null
            ? null
            : () {
                money!.toggle!();
                setPage(
                  () => display = MoneyDisplay(
                    display.huf ? 'EUR' : 'HUF',
                    display.rate,
                  ),
                );
              },
        child: ListingCard(
          item: widget.item,
          now: openedNow,
          loadDetails: widget.loadDetails,
          onUnavailable: widget.onUnavailable,
          unavailable: widget.unavailable,
          favorite: favorite,
          onFavorite: widget.onFavorite,
          onHide: widget.onHide,
          onWatch: widget.onWatch,
          watchThreshold: widget.watchThreshold,
          watchValue: widget.watchValue,
          onOpened: widget.onOpened,
          newLabel: widget.newLabel,
          showDeviceGroup: widget.showDeviceGroup,
          savedStatus: widget.savedStatus,
          detailed: true,
        ),
      ),
    );
    if (MediaQuery.sizeOf(context).width >= Ui.desktop) {
      await showDialog<void>(
        context: context,
        builder: (page) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(page).height * .9,
            child: view(page),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: view));
    }
  }

  Widget action(IconData icon, String label, VoidCallback? tap) =>
      OutlinedButton(
        onPressed: tap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          minimumSize: const Size(44, 48),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
  Widget detailView(BuildContext page) {
    final archive = now.difference(item.checkedAt) >= maxListingAge;
    final remaining = item.end?.difference(now);
    final stale = isUnchecked(item, now);
    final text = details?.description ?? details?.summary;
    final translation = [
      details?.condition,
      text,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join('\n\n');
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(page)),
        title: Text(
          deviceGroupLabels[item.deviceGroup]!,
          style: Theme.of(page).textTheme.bodyMedium,
        ),
      ),
      body: ListView(
        key: PageStorageKey('detail-${item.id}'),
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: image(190)),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: badges(full: true)),
          const SizedBox(height: 14),
          Text(item.title, style: Theme.of(page).textTheme.titleLarge),
          const SizedBox(height: 14),
          if (!archive)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _CardValue.price(
                      item.auction ? 'Aktuális licit' : 'Vételár',
                      item.effectivePrice,
                      item.currency,
                    ),
                    if (item.auction && item.bidCount != null)
                      _CardValue('Licitek száma', '${item.bidCount}'),
                    _CardValue.price(
                      'Szállítás Magyarországra',
                      item.shipping,
                      item.shippingCurrency,
                    ),
                    if (item.total != null) ...[
                      const Divider(),
                      _CardValue.price(
                        'Teljes ár',
                        item.total,
                        item.currency,
                        emphasize: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          _CardValue('Modell', item.model),
          _CardValue('Hely', '${countryName(item.country)} · eBay'),
          if (item.auction && item.end != null)
            _CardValue('Aukció vége', dateLabel(item.end!)),
          if (item.auction &&
              remaining != null &&
              !stale &&
              !widget.unavailable &&
              remaining > Duration.zero)
            _CardValue('Hátralévő idő', countdown(remaining), emphasize: true),
          _CardValue('Utoljára ellenőrizve', dateLabel(item.checkedAt)),
          const SizedBox(height: 14),
          ExpansionTile(
            key: const PageStorageKey('listing-description'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Leírás és az eladó megjegyzése'),
            onExpansionChanged: (_) => fetchDescription(),
            children: [
              if (loading)
                const LinearProgressIndicator()
              else if (error != null || widget.unavailable)
                Text(error ?? 'A hirdetés már nem elérhető')
              else if (details != null) ...[
                Text(
                  'Az eladó megjegyzése az állapotról',
                  style: Theme.of(page).textTheme.titleSmall,
                ),
                SelectableText(
                  key: const PageStorageKey('condition-text'),
                  details?.condition?.trim().isNotEmpty == true
                      ? details!.condition!
                      : 'Az eladó nem adott meg megjegyzést.',
                ),
                const SizedBox(height: 10),
                Text('Leírás', style: Theme.of(page).textTheme.titleSmall),
                SelectableText(
                  key: const PageStorageKey('description-text'),
                  text?.trim().isNotEmpty == true
                      ? text!
                      : 'Az eladó nem adott meg leírást.',
                ),
                if (translation.isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        openExternal(page, translationLink(translation)),
                    icon: const Icon(Icons.translate),
                    label: const Text('Google Fordító megnyitása'),
                  ),
              ],
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Ui.panel,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: action(
                      favorite ? Icons.favorite : Icons.favorite_border,
                      'Kedvenc',
                      widget.onFavorite == null ? null : toggleFavorite,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: action(
                      Icons.notifications_outlined,
                      'Figyelés',
                      item.auction &&
                              !archive &&
                              !widget.unavailable &&
                              remaining != null &&
                              remaining > Duration.zero
                          ? widget.onWatch
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: action(
                      Icons.visibility_off_outlined,
                      'Elrejtés',
                      widget.onHide == null
                          ? null
                          : () {
                              Navigator.pop(page);
                              widget.onHide?.call();
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    widget.onOpened?.call();
                    openExternal(page, item.url);
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Megnyitás az eBay-en'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (widget.detailed) return detailView(context);
      final desktop = MediaQuery.sizeOf(context).width >= Ui.desktop;
      final archive = now.difference(item.checkedAt) >= maxListingAge;
      final money = MoneyScope.displayOf(context);
      final price = archive
          ? 'Nem ismert'
          : money.format(item.total ?? item.effectivePrice, item.currency);
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 5, runSpacing: 4, children: badges()),
          const SizedBox(height: 5),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${item.model} · ${countryName(item.country)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 7),
          InkWell(
            onTap: MoneyScope.maybeOf(context)?.toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(price, style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    archive
                        ? 'Nem ellenőrzött'
                        : item.shipping == null
                        ? '+ szállítás nem ismert'
                        : '${item.auction ? 'licit ' : ''}${money.format(item.effectivePrice, item.currency)} + ${money.format(item.shipping, item.shippingCurrency)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (widget.showDeviceGroup)
            Text(
              deviceGroupLabels[item.deviceGroup]!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      );
      final heart = IconButton(
        tooltip: favorite ? 'Eltávolítás a kedvencekből' : 'Kedvencekhez adás',
        onPressed: widget.onFavorite == null ? null : toggleFavorite,
        icon: Icon(favorite ? Icons.favorite : Icons.favorite_border, size: 20),
      );
      return Opacity(
        opacity: isUnchecked(item, now) ? .65 : 1,
        child: Card(
          child: InkWell(
            onTap: openDetails,
            borderRadius: BorderRadius.circular(16),
            child: desktop
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        children: [
                          image(150, width: double.infinity),
                          Positioned(right: 0, top: 0, child: heart),
                        ],
                      ),
                      Padding(padding: const EdgeInsets.all(12), child: body),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: image(76, width: 76),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: body),
                        heart,
                      ],
                    ),
                  ),
          ),
        ),
      );
    },
  );
}

class _CardValue extends StatelessWidget {
  const _CardValue(this.label, this.value, {this.emphasize = false})
    : currency = null,
      isPrice = false;
  const _CardValue.price(
    this.label,
    this.value,
    this.currency, {
    this.emphasize = false,
  }) : isPrice = true;
  final String label;
  final String? value, currency;
  final bool isPrice, emphasize;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: isPrice
              ? PriceText(
                  value,
                  currency,
                  style: TextStyle(
                    fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                    color: emphasize ? Ui.primary : Ui.text,
                  ),
                  textAlign: TextAlign.end,
                )
              : Text(value ?? 'Nem ismert', textAlign: TextAlign.end),
        ),
      ],
    ),
  );
}
