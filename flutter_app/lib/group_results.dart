import 'api/models.dart';
import 'listings.dart';

class GroupResults {
  GroupResults([Map<String, SearchResult> initial = const {}])
    : groups = Map.of(initial);
  final Map<String, SearchResult> groups;
  static Map<String, SearchResult> split(
    SearchResult result,
    Iterable<String> selected,
  ) => {
    for (final group in selected)
      group: SearchResult.fromJson({
        ...result.toCacheJson(),
        'countries': result.countries
            .map(
              (country) => {
                'country': country.country,
                'status': country.status,
                'queries': country.queries
                    .map(
                      (q) => {
                        'query': q.query,
                        'status': q.status,
                        'error': q.error,
                        'warnings': q.warnings,
                        'count': q.count,
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
        'listings': result.listings
            .where((item) => item.deviceGroup == group)
            .map((item) => item.toJson())
            .toList(),
        'unknown_shipping': result.unknownShipping
            .where((item) => item.deviceGroup == group)
            .map((item) => item.toJson())
            .toList(),
      }),
  };
  void replace(SearchResult result, Iterable<String> selected) =>
      groups.addAll(split(result, selected));
  Iterable<Listing> all(Iterable<String> selected) sync* {
    final unique = <String>{};
    for (final group in selected) {
      for (final item in groups[group]?.allListings ?? <Listing>[]) {
        if (unique.add('${item.source}:${item.id}')) yield item;
      }
    }
  }

  void details(String id, ListingDetails details) {
    for (final group in groups.keys.toList()) {
      final result = groups[group]!;
      if (!result.allListings.any((item) => item.id == id)) continue;
      final rows = result.allListings
          .map((item) => item.id == id ? details.update(item) : item)
          .toList();
      groups[group] = SearchResult.fromJson({
        ...serialize(result),
        'listings': rows
            .where((item) => item.shipping != null)
            .map((item) => item.toJson())
            .toList(),
        'unknown_shipping': rows
            .where((item) => item.shipping == null)
            .map((item) => item.toJson())
            .toList(),
      });
    }
  }

  Json toJson() => {
    'groups': {
      for (final entry in groups.entries) entry.key: serialize(entry.value),
    },
  };
  static GroupResults fromJson(Json data) {
    if (data.containsKey('groups')) {
      return GroupResults(
        object(data['groups']).map((key, value) {
          if (!deviceGroups.contains(key)) invalidResponse();
          return MapEntry(key, SearchResult.fromJson(value));
        }),
      );
    }
    final legacy = SearchResult.fromJson(data);
    final selected = legacy.allListings.map((item) => item.deviceGroup).toSet();
    return GroupResults(
      split(legacy, selected.isEmpty ? ['consoles', 'controllers'] : selected),
    );
  }

  static Json serialize(SearchResult result) => {
    ...result.toCacheJson(),
    'countries': result.countries
        .map(
          (country) => {
            'country': country.country,
            'status': country.status,
            'queries': country.queries
                .map(
                  (q) => {
                    'query': q.query,
                    'status': q.status,
                    'count': q.count,
                    'error': q.error,
                    'warnings': q.warnings,
                  },
                )
                .toList(),
          },
        )
        .toList(),
  };
  void expire(DateTime now) {
    for (final entry in groups.entries.toList()) {
      final result = entry.value;
      groups[entry.key] = SearchResult.fromJson({
        ...serialize(result),
        'listings': result.listings
            .where((item) => now.difference(item.checkedAt) < maxListingAge)
            .map((item) => item.toJson())
            .toList(),
        'unknown_shipping': result.unknownShipping
            .where((item) => now.difference(item.checkedAt) < maxListingAge)
            .map((item) => item.toJson())
            .toList(),
      });
    }
  }
}
