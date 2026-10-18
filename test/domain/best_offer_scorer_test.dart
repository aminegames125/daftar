import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/domain/use_cases/best_offer_scorer.dart';
import 'package:daftar/domain/use_cases/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 16, 12);
const user = (lat: 36.80, lng: 10.18);

/// A place [km] kilometres north of the user (1 degree of latitude is ~111.2 km).
double lat(double km) => user.lat + km / 111.195;

OfferInput offer(
  String id, {
  int millimes = 1000,
  String? placeId = 'p',
  String? globalTypeId,
  double? km,
  bool located = true,
  int daysAgo = 0,
  DateTime? promoEndsAt,
  bool promo = false,
  int? baseQuantity,
  SizeDimension? dimension,
  String variantId = 'v',
}) => OfferInput(
  entry: PriceEntry(
    id: id,
    variantId: variantId,
    placeId: placeId,
    globalTypeId: globalTypeId,
    amount: Money.tnd(millimes),
    seenAt: now.subtract(Duration(days: daysAgo)),
    isPromo: promo || promoEndsAt != null,
    promoEndsAt: promoEndsAt,
  ),
  placeLat: located && placeId != null ? lat(km ?? 0) : null,
  placeLng: located && placeId != null ? user.lng : null,
  baseQuantity: baseQuantity,
  dimension: dimension,
);

OfferInput atPlace(
  String id,
  String placeId,
  int millimes, {
  double km = 0,
  int daysAgo = 0,
}) => offer(id, placeId: placeId, millimes: millimes, km: km, daysAgo: daysAgo);

void main() {
  const scorer = BestOfferScorer();

  group('basis', () {
    test('compares raw amounts when no size is known', () {
      final r = scorer.score([
        atPlace('a', 'a', 5000),
        atPlace('b', 'b', 4000),
      ], now: now)!;
      expect(r.basis, PriceBasis.raw);
      expect(r.best.entry.id, 'b');
      expect(r.best.unitPrice, isNull);
    });

    test('compares unit price per 100 g when every offer has a mass size', () {
      // 200 g at 5.000 (2.500/100 g) beats 100 g at 3.000 (3.000/100 g).
      final r = scorer.score([
        offer(
          'small',
          placeId: 'a',
          millimes: 3000,
          baseQuantity: 100,
          dimension: SizeDimension.mass,
        ),
        offer(
          'big',
          placeId: 'b',
          millimes: 5000,
          baseQuantity: 200,
          dimension: SizeDimension.mass,
        ),
      ], now: now)!;
      expect(r.basis, PriceBasis.per100g);
      expect(r.best.entry.id, 'big');
      expect(r.best.unitPrice, const Money.tnd(2500));
      expect(r.reasons.first, 'Cheapest per 100 g');
    });

    test('per 100 ml for volumes and per piece for counts', () {
      final ml = scorer.score([
        offer(
          'a',
          placeId: 'a',
          millimes: 1500,
          baseQuantity: 1500,
          dimension: SizeDimension.volume,
        ),
      ], now: now)!;
      expect(ml.basis, PriceBasis.per100ml);
      expect(ml.best.unitPrice, const Money.tnd(100));

      final pc = scorer.score([
        offer(
          'a',
          placeId: 'a',
          millimes: 6000,
          baseQuantity: 6,
          dimension: SizeDimension.count,
        ),
      ], now: now)!;
      expect(pc.basis, PriceBasis.perPiece);
      expect(pc.best.unitPrice, const Money.tnd(1000));
    });

    test('falls back to raw amounts when one offer has no size', () {
      final r = scorer.score([
        offer(
          'sized',
          placeId: 'a',
          millimes: 3000,
          baseQuantity: 100,
          dimension: SizeDimension.mass,
        ),
        offer('plain', placeId: 'b', millimes: 4000),
      ], now: now)!;
      expect(r.basis, PriceBasis.raw);
    });

    test('falls back to raw amounts when dimensions differ', () {
      final r = scorer.score([
        offer(
          'g',
          placeId: 'a',
          millimes: 3000,
          baseQuantity: 100,
          dimension: SizeDimension.mass,
        ),
        offer(
          'ml',
          placeId: 'b',
          millimes: 4000,
          baseQuantity: 100,
          dimension: SizeDimension.volume,
        ),
      ], now: now)!;
      expect(r.basis, PriceBasis.raw);
    });

    test('a range scores on its minimum', () {
      final ranged = OfferInput(
        entry: PriceEntry(
          id: 'range',
          variantId: 'v',
          placeId: 'a',
          amount: const Money.tnd(3000),
          amountMax: const Money.tnd(9000),
          seenAt: now,
        ),
      );
      final r = scorer.score([ranged, atPlace('b', 'b', 4000)], now: now)!;
      expect(r.best.entry.id, 'range');
    });
  });

  group('distance', () {
    test('adds 2% per km', () {
      final r = scorer.score(
        [offer('a', millimes: 1000, km: 5)],
        now: now,
        from: user,
      )!;
      final km = r.best.distanceKm!;
      expect(km, closeTo(5, 0.01));
      expect(r.best.score, closeTo(1000 * (1 + 0.02 * km), 1e-6));
    });

    test('a nearer, slightly dearer offer can win', () {
      final r = scorer.score(
        [
          atPlace('far', 'far', 1000, km: 20),
          atPlace('near', 'near', 1100, km: 0.5),
        ],
        now: now,
        from: user,
      )!;
      expect(r.best.entry.id, 'near');
    });

    test('is capped at +25%', () {
      final r = scorer.score(
        [offer('a', millimes: 1000, km: 80)],
        now: now,
        from: user,
      )!;
      expect(r.best.score, closeTo(1250, 1e-6));
    });

    test('a place without a location counts 1.05 when the user is located', () {
      final r = scorer.score(
        [offer('online', millimes: 1000, located: false)],
        now: now,
        from: user,
      )!;
      expect(r.best.score, closeTo(1050, 1e-6));
      expect(r.best.distanceKm, isNull);
    });

    test(
      'nobody is penalised for distance when the user location is unknown',
      () {
        final r = scorer.score([
          offer('a', placeId: 'a', millimes: 1000, km: 30),
          offer('b', placeId: 'b', millimes: 1000, located: false),
        ], now: now)!;
        expect(r.ranked.map((s) => s.score), everyElement(closeTo(1000, 1e-6)));
      },
    );
  });

  group('freshness', () {
    test('no penalty up to the stale threshold', () {
      final r = scorer.score([
        offer('a', millimes: 1000, daysAgo: 90),
      ], now: now)!;
      expect(r.best.score, closeTo(1000, 1e-6));
      expect(r.best.isStale, isFalse);
    });

    test('+10% per extra month past the threshold', () {
      final r = scorer.score([
        offer('a', millimes: 1000, daysAgo: 120),
      ], now: now)!;
      expect(r.best.score, closeTo(1100, 1e-6));
      expect(r.best.isStale, isTrue);
    });

    test('is capped at +30%', () {
      final r = scorer.score([
        offer('a', millimes: 1000, daysAgo: 900),
      ], now: now)!;
      expect(r.best.score, closeTo(1300, 1e-6));
    });

    test('a fresh dearer offer beats a very old cheaper one', () {
      final r = scorer.score([
        atPlace('old', 'a', 1000, daysAgo: 400),
        atPlace('fresh', 'b', 1200),
      ], now: now)!;
      expect(r.best.entry.id, 'fresh');
    });

    test('staleDays comes from the settings', () {
      final r = const BestOfferScorer(staleDays: 30)
          .score([offer('a', millimes: 1000, daysAgo: 60)], now: now)!;
      expect(r.best.score, closeTo(1100, 1e-6));
    });
  });

  group('candidates', () {
    test('an expired promo is ignored and the older regular price counts', () {
      final r = scorer.score([
        offer('regular', placeId: 'a', millimes: 5000, daysAgo: 20),
        offer(
          'promo',
          placeId: 'a',
          millimes: 3000,
          daysAgo: 5,
          promoEndsAt: now.subtract(const Duration(days: 1)),
        ),
      ], now: now)!;
      expect(r.ranked, hasLength(1));
      expect(r.best.entry.id, 'regular');
    });

    test('a running promo wins and says so', () {
      final r = scorer.score([
        offer('regular', placeId: 'a', millimes: 5000, daysAgo: 20),
        offer(
          'promo',
          placeId: 'a',
          millimes: 3000,
          daysAgo: 1,
          promoEndsAt: DateTime(2026, 10, 20),
        ),
      ], now: now)!;
      expect(r.best.entry.id, 'promo');
      expect(r.reasons.last, 'Promo until 20 Oct');
    });

    test('only the newest price per place counts', () {
      final r = scorer.score([
        atPlace('old-cheap', 'a', 500, daysAgo: 10),
        atPlace('new-dear', 'a', 5000),
        atPlace('b', 'b', 4000),
      ], now: now)!;
      expect(r.ranked.map((s) => s.entry.id), ['b', 'new-dear']);
    });

    test('different variants at one place are both kept', () {
      final r = scorer.score([
        offer('oreo', variantId: 'oreo', placeId: 'a', millimes: 4400),
        offer('noisette', variantId: 'noisette', placeId: 'a', millimes: 4900),
      ], now: now)!;
      expect(r.ranked, hasLength(2));
    });

    test('returns null when there is nothing to compare', () {
      expect(scorer.score(const [], now: now), isNull);
    });
  });

  group('global prices', () {
    test('count 1.10 and never have a distance', () {
      final r = scorer.score(
        [offer('g', placeId: null, globalTypeId: 'ref', millimes: 1000)],
        now: now,
        from: user,
      )!;
      expect(r.best.score, closeTo(1100, 1e-6));
      expect(r.best.distanceKm, isNull);
    });

    test('a global price loses to an equal price at a nearby place', () {
      final r = scorer.score(
        [
          offer('g', placeId: null, globalTypeId: 'ref', millimes: 1000),
          atPlace('shop', 'a', 1000, km: 1),
        ],
        now: now,
        from: user,
      )!;
      expect(r.best.entry.id, 'shop');
    });

    test('a much cheaper global price can still win', () {
      final r = scorer.score(
        [
          offer('g', placeId: null, globalTypeId: 'ref', millimes: 800),
          atPlace('shop', 'a', 1000, km: 1),
        ],
        now: now,
        from: user,
      )!;
      expect(r.best.entry.id, 'g');
    });
  });

  group('ties', () {
    test('go to the nearer offer', () {
      // Both score exactly 1250: the far one is at the +25% cap.
      final r = scorer.score(
        [
          offer(
            'far',
            placeId: 'far',
            millimes: 1000,
            km: 30,
          ), // capped at +25%  -> 1250
          offer(
            'near',
            placeId: 'near',
            millimes: 1250,
            km: 0,
          ), // +0%           -> 1250
        ],
        now: now,
        from: user,
      )!;
      expect(r.best.entry.id, 'near');
    });

    test('then to the newer offer', () {
      final r = scorer.score([
        atPlace('older', 'a', 1000, daysAgo: 10),
        atPlace('newer', 'b', 1000, daysAgo: 2),
      ], now: now)!;
      expect(r.best.entry.id, 'newer');
    });

    test('are deterministic when everything is equal', () {
      final a = scorer.score([
        atPlace('b', 'b', 1000),
        atPlace('a', 'a', 1000),
      ], now: now)!;
      final b = scorer.score([
        atPlace('a', 'a', 1000),
        atPlace('b', 'b', 1000),
      ], now: now)!;
      expect(a.best.entry.id, b.best.entry.id);
    });
  });

  group('reasons', () {
    test('cheapest, distance, seen-ago in that order', () {
      final r = scorer.score(
        [
          atPlace('best', 'a', 4400, km: 1.2, daysAgo: 3),
          atPlace('other', 'b', 5500, km: 3.4, daysAgo: 14),
        ],
        now: now,
        from: user,
      )!;
      expect(r.reasons, ['Cheapest', '1.2 km', 'Seen 3 days ago']);
    });

    test('a winner that is not the cheapest has no "Cheapest" reason', () {
      final r = scorer.score(
        [
          atPlace('near', 'near', 1100, km: 0.2),
          atPlace('far', 'far', 1000, km: 25),
        ],
        now: now,
        from: user,
      )!;
      expect(r.best.entry.id, 'near');
      expect(r.reasons.first, '0.2 km');
      expect(r.reasons, isNot(contains('Cheapest')));
    });

    test('a single offer is not called the cheapest', () {
      final r = scorer.score([atPlace('only', 'a', 1000)], now: now)!;
      expect(r.reasons, ['Seen today']);
    });

    test('a stale winner is marked old', () {
      final r = scorer.score([
        atPlace('only', 'a', 1000, daysAgo: 130),
      ], now: now)!;
      expect(r.reasons.single, 'Seen 4 months ago · old');
    });

    test('there are never more than three', () {
      final r = scorer.score(
        [atPlace('a', 'a', 1000, km: 1), atPlace('b', 'b', 2000, km: 1)],
        now: now,
        from: user,
      )!;
      expect(r.reasons.length, lessThanOrEqualTo(kMaxReasons));
    });
  });

  group('relative time', () {
    test('wording', () {
      expect(relativeAge(now, now), 'today');
      expect(
        relativeAge(now.subtract(const Duration(days: 1)), now),
        'yesterday',
      );
      expect(
        relativeAge(now.subtract(const Duration(days: 3)), now),
        '3 days ago',
      );
      expect(
        relativeAge(now.subtract(const Duration(days: 14)), now),
        '2 weeks ago',
      );
      expect(
        relativeAge(now.subtract(const Duration(days: 130)), now),
        '4 months ago',
      );
      expect(
        relativeAge(now.subtract(const Duration(days: 800)), now),
        '2 years ago',
      );
    });

    test('short dates add the year only when it differs', () {
      expect(shortDate(DateTime(2026, 3, 12), now), '12 Mar');
      expect(shortDate(DateTime(2025, 3, 12), now), '12 Mar 2025');
    });
  });
}
