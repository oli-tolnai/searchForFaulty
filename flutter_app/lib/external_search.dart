// These public search URL formats are intentionally centralized for manual verification.
const externalSearchFormats = {
  ExternalMarket.jofogas: 'https://www.jofogas.hu/magyarorszag',
  ExternalMarket.hardverapro: 'https://hardverapro.hu/aprok/keres.php',
};

enum ExternalMarket {
  jofogas('Jófogás', 'q'),
  hardverapro('HardverApró', 'stext');

  const ExternalMarket(this.label, this.parameter);
  final String label, parameter;
}

Uri externalSearchUri(ExternalMarket site, String text) =>
    Uri.parse(externalSearchFormats[site]!)
        .replace(queryParameters: {site.parameter: text});

String externalSearchText(String group, Iterable<String> models) {
  final first = models.firstOrNull;
  final fallback =
      {
        'consoles': 'ps5',
        'controllers': 'dualsense',
        'switch': 'nintendo switch',
        'steam_deck': 'steam deck',
        'iphone': 'iphone',
        'gpu': 'videókártya',
      }[group] ??
      'ps5';
  final model = first ?? fallback;
  return '$model hibás';
}

const baseQueriesPerCountry = {
  'consoles': 2,
  'controllers': 4,
  'switch': 1,
  'steam_deck': 1,
  'iphone': 7,
  'gpu': 2,
};

int? estimatedBaseCalls(Iterable<String> groups) {
  var count = 0;
  for (final group in groups.toSet()) {
    final queries = baseQueriesPerCountry[group];
    if (queries == null) return null;
    count += queries * 27;
  }
  return count;
}
