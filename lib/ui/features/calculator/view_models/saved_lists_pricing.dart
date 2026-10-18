import '../../../../domain/models/money.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/saved_list.dart';
import '../../../../domain/use_cases/basket_optimizer.dart';

/// What a saved list costs today: the best store, its total and what is left
/// unpriced. Pure data, computed by [summarizeSavedList].
class SavedListSummary {
  const SavedListSummary({
    required this.items,
    required this.checkedCount,
    required this.bestPlaceId,
    required this.total,
    required this.unpricedCount,
    required this.unitPrices,
  });

  static const empty = SavedListSummary(
    items: [],
    checkedCount: 0,
    bestPlaceId: null,
    total: null,
    unpricedCount: 0,
    unitPrices: {},
  );

  final List<SavedListItem> items;
  final int checkedCount;

  /// Best store for the priced items; null when nothing has a price.
  final String? bestPlaceId;

  /// Total of the priced items at [bestPlaceId]; null when nothing is priced.
  final Money? total;

  /// Items without a price at the best store (typed lines and unknown prices).
  final int unpricedCount;

  /// Variant id -> unit price (best store's, else the cheapest known).
  final Map<String, Money> unitPrices;

  int get itemCount => items.length;
  bool get hasPrice => total != null;
  bool get isDone => items.isNotEmpty && checkedCount == items.length;
  double get progress => items.isEmpty ? 0 : checkedCount / items.length;
}

/// Prices a list with the latest offers. [offersByVariant] holds the current
/// offers (newest price per place) of each variant; global prices (no place)
/// are ignored because a store has to be picked.
SavedListSummary summarizeSavedList({
  required List<SavedListItem> items,
  required Map<String, List<PriceEntry>> offersByVariant,
  required DateTime now,
  BasketOptimizer optimizer = const BasketOptimizer(),
}) {
  final prices = <String, Map<String, PriceQuote>>{};
  final cheapest = <String, Money>{};
  for (final entry in offersByVariant.entries) {
    for (final offer in entry.value) {
      final placeId = offer.placeId;
      if (placeId == null || offer.variantId == null) continue;
      final age = now.difference(offer.seenAt).inDays;
      (prices[placeId] ??= {})[entry.key] = PriceQuote(
        offer.amount,
        ageDays: age < 0 ? 0 : age,
      );
      final c = cheapest[entry.key];
      if (c == null || offer.amount.compareTo(c) < 0) {
        cheapest[entry.key] = offer.amount;
      }
    }
  }
  final lines = [
    for (final i in items)
      if (i.variantId != null)
        BasketLine.count(i.variantId!, count: i.quantity),
  ];
  final best = lines.isEmpty
      ? null
      : optimizer.optimize(lines: lines, prices: prices).best;
  final unit = Map<String, Money>.of(cheapest);
  if (best != null) {
    for (final id in best.lineTotals.keys) {
      final q = prices[best.placeId]![id];
      if (q != null) unit[id] = q.unitPrice;
    }
  }
  final priced = best == null
      ? 0
      : items.where((i) => best.lineTotals.containsKey(i.variantId)).length;
  return SavedListSummary(
    items: items,
    checkedCount: items.where((i) => i.isChecked).length,
    bestPlaceId: best?.placeId,
    total: best?.total,
    unpricedCount: items.length - priced,
    unitPrices: Map.unmodifiable(unit),
  );
}
