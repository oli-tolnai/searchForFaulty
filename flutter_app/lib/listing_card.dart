import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api/models.dart';
import 'api/webapp.dart';
import 'listings.dart';

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
  });

  final Listing item;
  final DateTime now;
  final Future<ListingDetails> Function(String id) loadDetails;
  final VoidCallback onUnavailable;
  final bool unavailable;

  @override
  State<ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends State<ListingCard> {
  bool expanded = false;
  bool loading = false;
  ListingDetails? details;
  String? error;

  Future<void> toggleDetails() async {
    setState(() => expanded = !expanded);
    if (!expanded || loading || details != null || widget.unavailable) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.loadDetails(widget.item.id);
      if (mounted) setState(() => details = result);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      if (failure.code == 'listing_not_found') widget.onUnavailable();
      setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final remaining = item.end?.difference(widget.now);
    final stale = isUnchecked(item, widget.now);
    final detailsText = details?.description ?? details?.summary;
    final translation = [details?.condition, detailsText]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join('\n\n');
    const placeholder = ColoredBox(
      color: Color(0xff232a35),
      child: Center(
        child: Icon(
          Icons.sports_esports_outlined,
          size: 42,
          color: Color(0xff9aa8ba),
        ),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2.15,
            child: item.image == null
                ? placeholder
                : Image.network(
                    item.image.toString(),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => placeholder,
                    frameBuilder: (_, child, frame, synchronouslyLoaded) =>
                        frame == null && !synchronouslyLoaded
                        ? placeholder
                        : child,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    tag(
                      item.auction ? 'Aukció' : 'Fix ár',
                      item.auction
                          ? const Color(0xfff7c875)
                          : const Color(0xff84caff),
                    ),
                    if (item.type == 'console_bundle')
                      tag('Csomag', colors.secondary),
                    if (item.type == 'needs_review')
                      tag('Ellenőrzendő', colors.secondary),
                    if (item.type == 'mainboard')
                      tag('Alaplap', colors.secondary),
                    if (item.banned) tag('Tiltott (banned)', colors.error),
                    if (item.possiblyNotFaulty)
                      tag('Lehet, hogy nem hibás', colors.secondary),
                    if (item.auction &&
                        !stale &&
                        !widget.unavailable &&
                        remaining != null &&
                        remaining > day * 2)
                      tag(
                        'Korai licit – a végső ár várhatóan magasabb',
                        const Color(0xfff7c875),
                      ),
                    if (stale) tag('Nem ellenőrzött', colors.tertiary),
                    if (widget.unavailable)
                      tag('Valószínűleg lezárult', colors.error),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item.title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.model} · ${countryName(item.country)} · eBay',
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (item.faultSource == 'text')
                  const Text('A hiba a címből vagy a leírásból derül ki.'),
                const Divider(height: 24),
                _CardValue(
                  item.auction ? 'Aktuális licit' : 'Vételár',
                  money(item.effectivePrice, item.currency),
                ),
                if (item.auction && item.bidCount != null)
                  _CardValue('Licitek száma', '${item.bidCount}'),
                _CardValue(
                  'Szállítás Magyarországra',
                  money(item.shipping, item.shippingCurrency),
                ),
                if (item.total != null)
                  _CardValue(
                    'Teljes ár',
                    money(item.total, item.currency),
                    emphasize: true,
                  ),
                if (item.auction && remaining != null) ...[
                  _CardValue('Aukció vége', dateLabel(item.end!)),
                  if (!stale &&
                      !widget.unavailable &&
                      remaining > Duration.zero)
                    _CardValue(
                      'Hátralévő idő',
                      countdown(remaining),
                      emphasize: true,
                    ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Utoljára ellenőrizve: ${dateLabel(item.checkedAt)}',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => openExternal(context, item.url),
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: const Text('Megnyitás az eBay-en'),
                    ),
                    OutlinedButton.icon(
                      onPressed: toggleDetails,
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: const Text('Leírás'),
                    ),
                  ],
                ),
                if (expanded) ...[
                  const Divider(height: 24),
                  if (loading)
                    const LinearProgressIndicator()
                  else if (error != null || widget.unavailable)
                    Text(
                      error ?? 'A hirdetés már nem elérhető',
                      style: TextStyle(color: colors.error),
                    )
                  else if (details != null) ...[
                    Text(
                      'Az eladó megjegyzése az állapotról',
                      style: text.titleSmall,
                    ),
                    SelectableText(
                      details?.condition?.trim().isNotEmpty == true
                          ? details!.condition!
                          : 'Az eladó nem adott meg megjegyzést.',
                    ),
                    const SizedBox(height: 10),
                    Text('Leírás', style: text.titleSmall),
                    SelectableText(
                      detailsText?.trim().isNotEmpty == true
                          ? detailsText!
                          : 'Az eladó nem adott meg leírást.',
                    ),
                    if (translation.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => openExternal(
                            context,
                            translationLink(translation),
                          ),
                          icon: const Icon(Icons.translate),
                          label: const Text('Fordítás a Google Fordítóval'),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardValue extends StatelessWidget {
  const _CardValue(this.label, this.value, {this.emphasize = false});
  final String label, value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: emphasize ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
      ],
    ),
  );
}
