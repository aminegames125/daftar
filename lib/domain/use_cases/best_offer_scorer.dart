import 'dart:math' as math;

import '../models/money.dart';
import '../models/price_entry.dart';
import '../models/product.dart';
import 'current_offers.dart';
import 'relative_time.dart';

// ---------------------------------------------------------------------------
// Constants of the best-option score (docs/DATA_MODEL.md § 7). Tune them here.
// ---------------------------------------------------------------------------

/// Days after which a price is "old" when the caller passes no setting (D15).
const int kDefaultStaleDays = 90;

/// Distance: +2% per km, capped at +25%.
const double kDistancePenaltyPerKm = 0.02;
const double kDistancePenaltyCap = 0.25;

/// A place without a location (e.g. an online shop) when the user's own
/// location is known.
const double kUnknownPlaceLocationMult = 1.05;

/// A global price (not tied to any place) is trusted a little less.
const double kGlobalPriceMult = 1.10;

/// Freshness: +10% per month past the stale threshold, capped at +30%.
const double kStalePenaltyPerMonth = 0.10;
const double kStalePenaltyCap = 0.30;
const int kDaysPerMonth = 30;

/// Unit prices are shown "per 100 g" / "per 100 ml" (but per single piece).
const int kUnitPriceBase = 100;

/// At most this many reasons are shown under the winner.
const int kMaxReasons = 3;

/// Scores closer than this are a tie (floating-point noise).
const double kScoreEpsilon = 1e-9;

const double _earthRadiusKm = 6371.0088;

/// The user's position, when known.
typedef GeoPoint = ({double lat, double lng});

/// How offers were compared (DATA_MODEL § 7 step 2).
enum PriceBasis {
  /// Raw amounts: not every offer has a comparable size.
  raw,
  per100g,
  per100ml,
  perPiece;

  /// "per 100 g", "per 100 ml", "per piece"; empty for [raw].
  String get unitLabel => switch (this) {
    PriceBasis.raw => '',
    PriceBasis.per100g => 'per 100 g',
    PriceBasis.per100ml => 'per 100 ml',
    PriceBasis.perPiece => 'per piece',
  };

  /// "/ 100 g" style suffix for compact lists; empty for [raw].
  String get shortLabel => switch (this) {
    PriceBasis.raw => '',
    PriceBasis.per100g => '/ 100 g',
    PriceBasis.per100ml => '/ 100 ml',
    PriceBasis.perPiece => '/ pc',
  };
}

/// A price entry plus what the scorer needs to know about where / what it is.
/// Build one per history entry (or per current offer) before scoring.
class OfferInput {
  const OfferInput({
    required this.entry,
    this.placeLat,
    this.placeLng,
    this.baseQuantity,
    this.dimension,
  });

  final PriceEntry entry;

  /// Place location; both null for an online shop / a global price.
  final double? placeLat;
  final double? placeLng;

  /// Variant size normalised to g, ml or pieces (`Variant.baseQuantity`), if any.
  final int? baseQuantity;

  /// Dimension of [baseQuantity] (`SizeUnit.dimension`).
  final SizeDimension? dimension;

  bool get hasPlaceLocation => placeLat != null && placeLng != null;

  /// What the price is *for*: the variant or menu option. Newer prices replace
  /// older ones per subject and place, never across subjects.
  String get subjectKey => entry.variantId ?? entry.menuOptionId ?? '';
}

/// One scored offer.
class ScoredOffer {
  const ScoredOffer({
    required this.offer,
    required this.basisValue,
    required this.score,
    required this.distanceKm,
    required this.ageDays,
    required this.isStale,
    required this.unitPrice,
  });

  final OfferInput offer;

  PriceEntry get entry => offer.entry;

  /// The compared number before distance/freshness: a unit price or the raw
  /// amount, in minor units (an internal ranking value, not money).
  final double basisValue;

  /// Lower is better.
  final double score;

  /// Haversine km to the user, when both locations are known.
  final double? distanceKm;
  final int ageDays;
  final bool isStale;

  /// "per 100 g" price, when the comparison is by unit. Display only.
  final Money? unitPrice;
}

/// Everything the UI needs to show "Best option" and the other offers.
class BestOfferResult {
  const BestOfferResult({
    required this.ranked,
    required this.basis,
    required this.reasons,
  });

  /// Best first.
  final List<ScoredOffer> ranked;
  final PriceBasis basis;

  /// Why the winner won (max [kMaxReasons]).
  final List<String> reasons;

  ScoredOffer get best => ranked.first;
  List<ScoredOffer> get others => ranked.skip(1).toList();
}

/// Picks the best option among current offers: unit price + freshness +
/// distance, with the reasons it won (DATA_MODEL § 7).
class BestOfferScorer {
  const BestOfferScorer({this.staleDays = kDefaultStaleDays});

  final int staleDays;

  /// Scores [offers] (a price history is fine: only the current offer per place
  /// and variant counts, expired promos are dropped). Returns null when there is
  /// nothing to compare.
  BestOfferResult? score(
    Iterable<OfferInput> offers, {
    required DateTime now,
    GeoPoint? from,
  }) {
    final candidates = _candidates(offers, now);
    if (candidates.isEmpty) return null;

    final basis = _basisOf(candidates);
    final scored = [for (final c in candidates) _score(c, basis, now, from)]
      ..sort(_compare);
    final minBasis = scored.map((s) => s.basisValue).reduce(math.min);

    return BestOfferResult(
      ranked: scored,
      basis: basis,
      reasons: _reasons(scored.first, scored.length, minBasis, basis, now),
    );
  }

  /// Step 1: latest price per place (and per global type) for each variant /
  /// option, expired promos dropped. Reuses [currentOffers].
  List<OfferInput> _candidates(Iterable<OfferInput> offers, DateTime now) {
    final byEntryId = {for (final o in offers) o.entry.id: o};
    final bySubject = <String, List<PriceEntry>>{};
    for (final o in byEntryId.values) {
      bySubject.putIfAbsent(o.subjectKey, () => []).add(o.entry);
    }
    return [
      for (final entries in bySubject.values)
        for (final e in currentOffers(entries, now)) byEntryId[e.id]!,
    ];
  }

  /// Step 2: unit prices only when *every* candidate has a size in the same dimension.
  PriceBasis _basisOf(List<OfferInput> candidates) {
    final dimension = candidates.first.dimension;
    final comparable =
        dimension != null &&
        candidates.every(
          (c) => c.dimension == dimension && (c.baseQuantity ?? 0) > 0,
        );
    if (!comparable) return PriceBasis.raw;
    return switch (dimension) {
      SizeDimension.mass => PriceBasis.per100g,
      SizeDimension.volume => PriceBasis.per100ml,
      SizeDimension.count => PriceBasis.perPiece,
    };
  }

  ScoredOffer _score(
    OfferInput offer,
    PriceBasis basis,
    DateTime now,
    GeoPoint? from,
  ) {
    final entry = offer.entry;
    final minor = entry.amount.minor; // a range scores on its minimum
    final perUnit = basis == PriceBasis.perPiece ? 1 : kUnitPriceBase;
    final basisValue = basis == PriceBasis.raw
        ? minor.toDouble()
        : minor / offer.baseQuantity! * perUnit;

    double? km;
    if (from != null && offer.hasPlaceLocation) {
      km = _haversineKm(from.lat, from.lng, offer.placeLat!, offer.placeLng!);
    }
    final distMult = _distanceMult(offer, km, userLocated: from != null);

    final age = ageInDays(entry.seenAt, now);
    final freshMult = _freshnessMult(age);

    return ScoredOffer(
      offer: offer,
      basisValue: basisValue,
      score: basisValue * distMult * freshMult,
      distanceKm: km,
      ageDays: age,
      isStale: age > staleDays,
      unitPrice: basis == PriceBasis.raw
          ? null
          : Money(
              (minor * perUnit / offer.baseQuantity!).round(),
              entry.amount.currency,
            ),
    );
  }

  /// Step 3. Without the user's position nobody is penalised for distance
  /// (DECISION(owner): the 1.05 "unknown place" factor only applies when we
  /// could have measured the distance to a located place).
  double _distanceMult(
    OfferInput offer,
    double? km, {
    required bool userLocated,
  }) {
    if (offer.entry.isGlobal) return kGlobalPriceMult;
    if (km != null) {
      return 1 + math.min(kDistancePenaltyCap, kDistancePenaltyPerKm * km);
    }
    return userLocated ? kUnknownPlaceLocationMult : 1.0;
  }

  /// Step 4.
  double _freshnessMult(int ageDays) {
    if (ageDays <= staleDays) return 1.0;
    final extraMonths = (ageDays - staleDays) / kDaysPerMonth;
    return 1 + math.min(kStalePenaltyCap, kStalePenaltyPerMonth * extraMonths);
  }

  /// Step 5: lowest score; ties go to the nearer, then the newer, then the id.
  int _compare(ScoredOffer a, ScoredOffer b) {
    if ((a.score - b.score).abs() > kScoreEpsilon) {
      return a.score.compareTo(b.score);
    }
    final da = a.distanceKm, db = b.distanceKm;
    if (da != db) {
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    }
    final byAge = a.ageDays.compareTo(b.ageDays);
    return byAge != 0 ? byAge : a.entry.id.compareTo(b.entry.id);
  }

  /// Step 6.
  List<String> _reasons(
    ScoredOffer winner,
    int count,
    double minBasis,
    PriceBasis basis,
    DateTime now,
  ) {
    final entry = winner.entry;
    final reasons = <String>[];

    // DECISION(owner): "Cheapest" is not claimed when there is only one offer.
    if (count > 1 && (winner.basisValue - minBasis).abs() <= kScoreEpsilon) {
      reasons.add(
        basis == PriceBasis.raw ? 'Cheapest' : 'Cheapest ${basis.unitLabel}',
      );
    }
    if (winner.distanceKm != null) reasons.add(formatKm(winner.distanceKm!));

    if (entry.isPromo && entry.promoEndsAt != null) {
      reasons.add('Promo until ${shortDate(entry.promoEndsAt!, now)}');
    } else if (entry.isPromo) {
      reasons.add('Promo');
    } else {
      final seen = 'Seen ${relativeAge(entry.seenAt, now)}';
      reasons.add(winner.isStale ? '$seen · old' : seen);
    }
    return reasons.take(kMaxReasons).toList();
  }
}

/// Great-circle distance in km.
double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusKm * math.asin(math.min(1, math.sqrt(a)));
}

/// Haversine distance in km, exposed for the UI ("0.8 km") and tests.
double distanceKm(double lat1, double lng1, double lat2, double lng2) =>
    _haversineKm(lat1, lng1, lat2, lng2);
