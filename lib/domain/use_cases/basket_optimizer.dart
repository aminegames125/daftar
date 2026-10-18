import '../models/money.dart';
import 'best_offer_scorer.dart' show kDefaultStaleDays;

/// Default saving (1.000 TND) below which a second trip is "not worth it".
const Money kDefaultSplitWorthThreshold = Money.tnd(1000);

/// One line of a basket. [key] is a product or variant id (the caller decides
/// the granularity, as long as it matches the price map keys).
class BasketLine {
  /// [quantityMilli] is the quantity in thousandths (1000 = 1, 1500 = 1.5 kg),
  /// so no `double` is ever involved.
  const BasketLine({required this.key, this.label, this.quantityMilli = 1000});

  /// A whole-number quantity.
  const BasketLine.count(this.key, {int count = 1, this.label})
    : quantityMilli = count * 1000;

  final String key;
  final String? label;
  final int quantityMilli;
}

/// The latest known unit price of a product in a place and how old it is.
class PriceQuote {
  const PriceQuote(this.unitPrice, {this.ageDays = 0});
  final Money unitPrice;
  final int ageDays;
}

/// Why a store (or the split) is recommended. Structured, rendered by the UI.
sealed class BasketReason {
  const BasketReason();
}

/// Lowest total among the stores that price every line.
class CheapestTotalReason extends BasketReason {
  const CheapestTotalReason();
}

/// Prices every one of [count] lines.
class CoversAllReason extends BasketReason {
  const CoversAllReason(this.count);
  final int count;
}

/// Prices only [covered] of [total] lines.
class CoversPartialReason extends BasketReason {
  const CoversPartialReason(this.covered, this.total);
  final int covered;
  final int total;
}

/// [count] lines have no known price here.
class MissingItemsReason extends BasketReason {
  const MissingItemsReason(this.count);
  final int count;
}

/// Cheaper than the next best comparable store by [saving].
class SavesVersusNextReason extends BasketReason {
  const SavesVersusNextReason(this.saving);
  final Money saving;
}

/// Same total as another store; broken by freshness then id.
class TiedReason extends BasketReason {
  const TiedReason();
}

/// The oldest price used is [days] days old (still fresh).
class PricesAgeReason extends BasketReason {
  const PricesAgeReason(this.days);
  final int days;
}

/// [count] prices are older than the stale threshold (oldest [oldestDays]).
class StalePricesReason extends BasketReason {
  const StalePricesReason(this.count, this.oldestDays);
  final int count;
  final int oldestDays;
}

/// Only one store has any price for the basket.
class OnlyStoreReason extends BasketReason {
  const OnlyStoreReason();
}

/// The split uses [stores] stores and saves [saving] versus the best store.
class SplitSavesReason extends BasketReason {
  const SplitSavesReason(this.stores, this.saving);
  final int stores;
  final Money saving;
}

/// The split saves less than the threshold: not worth another trip.
class NotWorthSecondTripReason extends BasketReason {
  const NotWorthSecondTripReason(this.saving, this.threshold);
  final Money saving;
  final Money threshold;
}

/// A store's result for the whole basket.
class StoreBasket {
  const StoreBasket({
    required this.placeId,
    required this.total,
    required this.lineTotals,
    required this.coveredCount,
    required this.totalLines,
    required this.missingKeys,
    required this.staleKeys,
    required this.oldestAgeDays,
    required this.savingVersusNext,
    required this.reasons,
  });

  final String placeId;

  /// Sum of the priced lines (all of them when [isComplete]).
  final Money total;

  /// Line key -> line total, only for priced lines.
  final Map<String, Money> lineTotals;
  final int coveredCount;
  final int totalLines;
  final List<String> missingKeys;
  final List<String> staleKeys;

  /// Age of the oldest price used; null when nothing is priced.
  final int? oldestAgeDays;

  /// Next comparable store's total minus this one's. Only set when both have
  /// the same coverage (otherwise totals are not comparable); null for the last.
  final Money? savingVersusNext;
  final List<BasketReason> reasons;

  bool get isComplete => totalLines > 0 && coveredCount == totalLines;
  double get coverage => totalLines == 0 ? 0 : coveredCount / totalLines;
}

/// One line of the cheapest split.
class SplitAssignment {
  const SplitAssignment(this.key, this.placeId, this.lineTotal);
  final String key;
  final String placeId;
  final Money lineTotal;
}

/// "Buy each line where it is cheapest".
class CheapestSplit {
  const CheapestSplit({
    required this.assignments,
    required this.perStore,
    required this.total,
    required this.unpricedKeys,
    required this.savingVersusBest,
    required this.threshold,
    required this.reasons,
  });

  final List<SplitAssignment> assignments;

  /// Place id -> subtotal bought there.
  final Map<String, Money> perStore;
  final Money total;
  final List<String> unpricedKeys;

  /// Best single store's cost of the lines it prices minus the split's cost of
  /// those same lines. Null when there is no best store.
  final Money? savingVersusBest;
  final Money threshold;
  final List<BasketReason> reasons;

  int get storesUsed => perStore.length;

  /// True when it needs 2+ stores and saves at least [threshold].
  bool get isWorthIt =>
      storesUsed > 1 &&
      savingVersusBest != null &&
      savingVersusBest!.minor >= threshold.minor;
}

class BasketOptimization {
  const BasketOptimization({
    required this.stores,
    required this.best,
    required this.split,
  });

  /// Ranked best first: by coverage, then total, then freshness, then id.
  final List<StoreBasket> stores;
  final StoreBasket? best;
  final CheapestSplit? split;
}

/// Compares a basket across places (see DATA_MODEL § 9).
class BasketOptimizer {
  const BasketOptimizer();

  /// Line total = unit price x quantity, rounded half up to the millime.
  static Money lineTotal(Money unit, int quantityMilli) {
    final raw = unit.minor * quantityMilli;
    final q = (raw.abs() + 500) ~/ 1000;
    return Money(raw < 0 ? -q : q, unit.currency);
  }

  /// [prices]: place id -> line key -> latest quote.
  BasketOptimization optimize({
    required List<BasketLine> lines,
    required Map<String, Map<String, PriceQuote>> prices,
    int staleDays = kDefaultStaleDays,
    Money splitThreshold = kDefaultSplitWorthThreshold,
  }) {
    final merged = _merge(lines);
    if (merged.isEmpty) {
      return const BasketOptimization(stores: [], best: null, split: null);
    }
    final totalLines = merged.length;
    final raws = <_Raw>[];
    final placeIds = prices.keys.toList()..sort();
    for (final placeId in placeIds) {
      final quotes = prices[placeId]!;
      final lineTotals = <String, Money>{};
      final missing = <String>[];
      final stale = <String>[];
      var sum = 0;
      int? oldest;
      var currency = splitThreshold.currency;
      for (final e in merged.entries) {
        final q = quotes[e.key];
        if (q == null) {
          missing.add(e.key);
          continue;
        }
        final t = lineTotal(q.unitPrice, e.value.quantityMilli);
        currency = t.currency;
        lineTotals[e.key] = t;
        sum += t.minor;
        if (q.ageDays > staleDays) stale.add(e.key);
        if (oldest == null || q.ageDays > oldest) oldest = q.ageDays;
      }
      if (lineTotals.isEmpty) continue; // knows nothing about the basket
      raws.add(
        _Raw(placeId, Money(sum, currency), lineTotals, missing, stale, oldest),
      );
    }

    raws.sort((a, b) {
      final c = b.lineTotals.length.compareTo(a.lineTotals.length);
      if (c != 0) return c;
      final t = a.total.minor.compareTo(b.total.minor);
      if (t != 0) return t;
      final age = (a.oldest ?? 0).compareTo(b.oldest ?? 0);
      if (age != 0) return age;
      return a.placeId.compareTo(b.placeId);
    });

    final stores = <StoreBasket>[];
    final completeCount = raws
        .where((r) => r.lineTotals.length == totalLines)
        .length;
    for (var i = 0; i < raws.length; i++) {
      final r = raws[i];
      final next = i + 1 < raws.length ? raws[i + 1] : null;
      Money? saving;
      var tied = false;
      if (next != null && next.lineTotals.length == r.lineTotals.length) {
        saving = next.total - r.total;
        tied = saving.minor == 0;
      }
      final isComplete = r.lineTotals.length == totalLines;
      final reasons = <BasketReason>[];
      if (i == 0 && isComplete && completeCount > 1 && !tied) {
        reasons.add(const CheapestTotalReason());
      }
      if (i == 0 && raws.length == 1) reasons.add(const OnlyStoreReason());
      if (isComplete) {
        reasons.add(CoversAllReason(totalLines));
      } else {
        reasons.add(CoversPartialReason(r.lineTotals.length, totalLines));
        reasons.add(MissingItemsReason(r.missing.length));
      }
      if (i == 0 && saving != null && saving.minor > 0) {
        reasons.add(SavesVersusNextReason(saving));
      }
      if (tied) reasons.add(const TiedReason());
      if (r.stale.isNotEmpty) {
        reasons.add(StalePricesReason(r.stale.length, r.oldest!));
      } else if (r.oldest != null && r.oldest! > 0) {
        reasons.add(PricesAgeReason(r.oldest!));
      }
      stores.add(
        StoreBasket(
          placeId: r.placeId,
          total: r.total,
          lineTotals: Map.unmodifiable(r.lineTotals),
          coveredCount: r.lineTotals.length,
          totalLines: totalLines,
          missingKeys: List.unmodifiable(r.missing),
          staleKeys: List.unmodifiable(r.stale),
          oldestAgeDays: r.oldest,
          savingVersusNext: saving,
          reasons: List.unmodifiable(reasons),
        ),
      );
    }

    final best = stores.isEmpty ? null : stores.first;
    final split = best == null
        ? null
        : _split(merged, raws, best, splitThreshold);
    return BasketOptimization(
      stores: List.unmodifiable(stores),
      best: best,
      split: split,
    );
  }

  CheapestSplit _split(
    Map<String, BasketLine> merged,
    List<_Raw> raws,
    StoreBasket best,
    Money threshold,
  ) {
    final assignments = <SplitAssignment>[];
    final unpriced = <String>[];
    final perStore = <String, int>{};
    var total = 0;
    var currency = threshold.currency;
    for (final key in merged.keys) {
      String? pick;
      Money? pickTotal;
      for (final r in raws) {
        final t = r.lineTotals[key];
        if (t == null) continue;
        final better =
            pickTotal == null ||
            t.minor < pickTotal.minor ||
            (t.minor == pickTotal.minor &&
                r.placeId == best.placeId &&
                pick != best.placeId);
        if (better) {
          pick = r.placeId;
          pickTotal = t;
        }
      }
      if (pick == null) {
        unpriced.add(key);
        continue;
      }
      currency = pickTotal!.currency;
      assignments.add(SplitAssignment(key, pick, pickTotal));
      perStore[pick] = (perStore[pick] ?? 0) + pickTotal.minor;
      total += pickTotal.minor;
    }
    var bestCovered = 0;
    for (final a in assignments) {
      if (best.lineTotals.containsKey(a.key)) bestCovered += a.lineTotal.minor;
    }
    final saving = Money(best.total.minor - bestCovered, currency);
    final stores = perStore.length;
    final worth = stores > 1 && saving.minor >= threshold.minor;
    final reasons = <BasketReason>[
      if (worth) SplitSavesReason(stores, saving),
      if (!worth && stores > 1) NotWorthSecondTripReason(saving, threshold),
    ];
    final sortedStores = perStore.keys.toList()..sort();
    return CheapestSplit(
      assignments: List.unmodifiable(assignments),
      perStore: Map.unmodifiable({
        for (final k in sortedStores) k: Money(perStore[k]!, currency),
      }),
      total: Money(total, currency),
      unpricedKeys: List.unmodifiable(unpriced),
      savingVersusBest: saving,
      threshold: threshold,
      reasons: List.unmodifiable(reasons),
    );
  }

  Map<String, BasketLine> _merge(List<BasketLine> lines) {
    final out = <String, BasketLine>{};
    for (final l in lines) {
      if (l.quantityMilli <= 0) {
        throw ArgumentError('Quantity must be positive: ${l.key}');
      }
      final prev = out[l.key];
      out[l.key] = prev == null
          ? l
          : BasketLine(
              key: l.key,
              label: prev.label ?? l.label,
              quantityMilli: prev.quantityMilli + l.quantityMilli,
            );
    }
    return out;
  }
}

class _Raw {
  _Raw(
    this.placeId,
    this.total,
    this.lineTotals,
    this.missing,
    this.stale,
    this.oldest,
  );
  final String placeId;
  final Money total;
  final Map<String, Money> lineTotals;
  final List<String> missing;
  final List<String> stale;
  final int? oldest;
}
