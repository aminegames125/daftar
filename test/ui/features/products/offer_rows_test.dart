import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/domain/use_cases/best_offer_scorer.dart';
import 'package:daftar/domain/use_cases/filter_products.dart';
import 'package:daftar/ui/features/products/view_models/offer_rows.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 16, 12);

PriceEntry entry(
  String id,
  String? placeId,
  int millimes,
  int daysAgo, {
  String? type,
  bool promo = false,
}) => PriceEntry(
  id: id,
  variantId: 'v',
  placeId: placeId,
  globalTypeId: type,
  amount: Money.tnd(millimes),
  seenAt: now.subtract(Duration(days: daysAgo)),
  isPromo: promo,
);

void main() {
  const places = {
    'abc': Place(
      id: 'abc',
      name: 'Store ABC',
      typeId: 't',
      lat: 36.8,
      lng: 10.18,
    ),
    'cbc': Place(
      id: 'cbc',
      name: 'Store CBC',
      typeId: 't',
      lat: 36.9,
      lng: 10.18,
    ),
    'corner': Place(id: 'corner', name: 'Corner shop', typeId: 't'),
  };
  const types = {'ref': GlobalPriceType(id: 'ref', name: 'Reference price')};
  const oreo = Variant(
    id: 'v',
    productId: 'p',
    name: 'Oreo',
    sizeValue: 100,
    sizeUnit: SizeUnit.g,
  );

  OffersView view(List<PriceEntry> history, {GeoPoint? from}) =>
      buildOffersView(
        history: history,
        variant: oreo,
        places: places,
        types: types,
        now: now,
        staleDays: 90,
        from: from,
      );

  group('buildOffersView', () {
    test('ranks offers, marks the best and the stale ones', () {
      final v = view([
        entry('abc', 'abc', 4400, 3),
        entry('cbc', 'cbc', 5500, 14),
        entry('corner', 'corner', 4900, 120),
      ]);

      expect(v.rows.map((r) => r.title), [
        'Store ABC',
        'Corner shop',
        'Store CBC',
      ]);
      expect(v.best!.isBest, isTrue);
      expect(v.rows.skip(1).any((r) => r.isBest), isFalse);
      expect(
        v.rows.firstWhere((r) => r.title == 'Corner shop').isStale,
        isTrue,
      );
      expect(v.basis, PriceBasis.per100g);
      expect(v.best!.unitPrice, const Money.tnd(4400));
      expect(v.reasons.first, 'Cheapest per 100 g');
    });

    test('distance comes from the user location', () {
      final v = view(
        [entry('abc', 'abc', 4400, 3), entry('cbc', 'cbc', 4400, 3)],
        from: (lat: 36.8, lng: 10.18),
      );
      expect(v.best!.title, 'Store ABC');
      expect(v.best!.distanceKm, closeTo(0, 0.01));
      expect(v.rows.last.distanceKm, closeTo(11.1, 0.2));
    });

    test('global prices carry their type label', () {
      final v = view([entry('g', null, 4000, 5, type: 'ref')]);
      expect(v.best!.title, 'Reference price');
      expect(v.best!.place, isNull);
    });

    test('change labels compare with the previous price at the same store', () {
      final v = view([
        entry('new', 'abc', 5000, 2),
        entry('old', 'abc', 4000, 60),
      ]);
      expect(v.rows.single.change!.percent, 25);
    });

    test('a removed place is called so instead of crashing', () {
      final v = view([entry('x', 'gone', 4000, 2)]);
      expect(v.best!.title, 'Removed place');
    });

    test('no history gives the empty view', () {
      expect(view(const []).best, isNull);
    });
  });

  group('buildChartSeries', () {
    test('one line per store, oldest point first, busiest store first', () {
      final series = buildChartSeries(
        history: [
          entry('a2', 'abc', 4800, 1),
          entry('a1', 'abc', 4400, 40),
          entry('b1', 'cbc', 5500, 20),
        ],
        places: places,
        types: types,
        bestTitle: 'Store CBC',
      );
      expect(series.map((s) => s.label), ['Store ABC', 'Store CBC']);
      expect(series.first.points.map((p) => p.value), [4.4, 4.8]);
      expect(
        series.first.points.first.at.isBefore(series.first.points.last.at),
        isTrue,
      );
      expect(series.last.isBest, isTrue);
    });

    test('caps the number of lines', () {
      final history = [
        for (var i = 0; i < 8; i++) entry('e$i', 'p$i', 1000 + i, i),
      ];
      expect(
        buildChartSeries(history: history, places: places, types: types).length,
        5,
      );
    });
  });

  group('filterProducts', () {
    const products = [
      Product(
        id: '1',
        name: 'Milka',
        categoryId: 'food',
        variants: [
          Variant(id: 'a', productId: '1', name: 'Oreo', barcode: '619'),
        ],
      ),
      Product(id: '2', name: 'Cola', categoryId: 'drinks'),
      Product(id: '3', name: 'Chocolat noir', categoryId: 'food'),
    ];

    test('by category', () {
      expect(filterProducts(products, categoryId: 'food').map((p) => p.id), [
        '3',
        '1',
      ]);
    });

    test('by query, including variant names and barcodes', () {
      expect(filterProducts(products, query: 'oreo').map((p) => p.id), ['1']);
      expect(filterProducts(products, query: '619').map((p) => p.id), ['1']);
      expect(
        filterProducts(
          products,
          query: 'CHOCOLAT',
          categoryId: 'food',
        ).map((p) => p.id),
        ['3'],
      );
      expect(filterProducts(products, query: 'zzz'), isEmpty);
    });
  });
}
