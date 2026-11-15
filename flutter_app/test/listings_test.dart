import 'package:flutter_app/api/models.dart';
import 'package:flutter_app/listings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/responses.dart';

void main() {
  test('missing nullable fields and invalid amounts fail while seller data is discarded', () {
    final missing = listing()..remove('shipping_cost');
    expect(() => Listing.fromJson(missing), throwsFormatException);
    expect(
      () => Listing.fromJson({...listing(), 'price': 'NaN'}),
      throwsFormatException,
    );
    expect(
      () => Listing.fromJson({...listing(), 'total_price': '75'}),
      throwsFormatException,
    );
    expect(
      () => SearchResult.fromJson(search()..remove('daily_api_calls')),
      throwsFormatException,
    );
    final result = SearchResult.fromJson(
      search(
        unknown: [
          {
            ...listing(),
            'seller': {'username': 'private'},
          },
        ],
      ),
    );
    expect(result.unknownShipping.single.shipping, isNull);
    expect(result.toCacheJson().toString(), isNot(contains('private')));
  });

  test('max total leaves unknown shipping and the auction filter leaves fixed prices', () {
    final result = [
      Listing.fromJson(listing(id: 'known', shipping: '20', total: '95')),
      Listing.fromJson(listing(id: 'fixed')),
      Listing.fromJson(listing(id: 'soon', end: testTime.add(day))),
      Listing.fromJson(listing(id: 'late', end: testTime.add(day * 2))),
      Listing.fromJson(listing(id: 'expired', end: testTime)),
    ];
    final visible = selectListings(
      result,
      const ListingFilters(maxTotal: 90, endingSoon: true),
      ListingOrder.total,
      testTime,
    );
    expect(visible.map((item) => item.id), ['fixed', 'soon']);
  });

  test(
    'newest sorts dates first and leaves unknown shipping in its own section',
    () {
      final visible = selectListings(
        [
          Listing.fromJson(listing(id: 'undated')),
          Listing.fromJson(
            listing(id: 'older', listedAt: testTime.subtract(day)),
          ),
          Listing.fromJson(listing(id: 'newer', listedAt: testTime)),
          Listing.fromJson(listing(id: 'known', shipping: '10', total: '85')),
        ],
        const ListingFilters(),
        ListingOrder.newest,
        testTime,
      );
      expect(visible.map((item) => item.id), [
        'known',
        'newer',
        'older',
        'undated',
      ]);
    },
  );
}
