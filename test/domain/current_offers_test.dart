import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/use_cases/current_offers.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 16);

PriceEntry entry(
  String id, {
  String? placeId = 'a',
  String? globalTypeId,
  int millimes = 1000,
  int daysAgo = 0,
  DateTime? promoEndsAt,
}) => PriceEntry(
  id: id,
  variantId: 'v',
  placeId: placeId,
  globalTypeId: globalTypeId,
  amount: Money.tnd(millimes),
  seenAt: now.subtract(Duration(days: daysAgo)),
  isPromo: promoEndsAt != null,
  promoEndsAt: promoEndsAt,
);

void main() {
  group('currentOffers', () {
    test('keeps the newest entry per place', () {
      final result = currentOffers([
        entry('old', daysAgo: 30),
        entry('new', daysAgo: 2),
        entry('b', placeId: 'b'),
      ], now);
      expect(result.map((e) => e.id), unorderedEquals(['new', 'b']));
    });

    test('an expired promo falls back to the older regular price', () {
      final result = currentOffers([
        entry('regular', millimes: 5000, daysAgo: 20),
        entry(
          'promo',
          millimes: 3000,
          daysAgo: 5,
          promoEndsAt: now.subtract(const Duration(days: 1)),
        ),
      ], now);
      expect(result.single.id, 'regular');
    });

    test('a running promo wins', () {
      final result = currentOffers([
        entry('regular', daysAgo: 20),
        entry(
          'promo',
          daysAgo: 1,
          promoEndsAt: now.add(const Duration(days: 3)),
        ),
      ], now);
      expect(result.single.id, 'promo');
    });

    test('global prices are kept per type', () {
      final result = currentOffers([
        entry('ref', placeId: null, globalTypeId: 'reference'),
        entry('official', placeId: null, globalTypeId: 'official'),
        entry('ref-old', placeId: null, globalTypeId: 'reference', daysAgo: 9),
      ], now);
      expect(result.map((e) => e.id), unorderedEquals(['ref', 'official']));
    });
  });
}
