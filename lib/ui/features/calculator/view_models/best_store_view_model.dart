import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/basket.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/use_cases/basket_optimizer.dart';
import '../../places/view_models/places_providers.dart';
import 'calculator_providers.dart';

/// What Best store shows: the optimizer result plus the names it needs.
class BestStoreState {
  const BestStoreState({
    required this.optimization,
    required this.placeNames,
    required this.itemNames,
    required this.skippedCount,
  });

  final BasketOptimization optimization;

  /// Place id -> display name.
  final Map<String, String> placeNames;

  /// Line key (variant id) -> item name.
  final Map<String, String> itemNames;

  /// Basket lines typed by hand (no catalog link): they cannot be compared.
  final int skippedCount;

  String placeName(String id) => placeNames[id] ?? 'Unknown place';
  String itemName(String key) => itemNames[key] ?? 'Item';
}

/// The optimizer lines for a basket: one per catalog variant, quantity in
/// thousandths. Hand-typed lines have no key and are counted in `skipped`.
({List<BasketLine> lines, int skipped}) basketLines(Basket basket) {
  final lines = <BasketLine>[];
  var skipped = 0;
  for (final item in basket.items) {
    final key = item.variantId;
    if (key == null) {
      skipped++;
    } else {
      lines.add(
        BasketLine(
          key: key,
          label: item.name,
          quantityMilli: item.quantity * 1000,
        ),
      );
    }
  }
  return (lines: lines, skipped: skipped);
}

/// Place id -> variant id -> latest quote, from each variant's current offers
/// (global prices have no place and are ignored). Age is whole days since
/// [PriceEntry.seenAt], never negative.
Map<String, Map<String, PriceQuote>> buildPriceMap(
  Map<String, List<PriceEntry>> offersByVariant,
  DateTime now,
) {
  final out = <String, Map<String, PriceQuote>>{};
  offersByVariant.forEach((variantId, offers) {
    for (final o in offers) {
      final placeId = o.placeId;
      if (placeId == null) continue;
      final days = now.difference(o.seenAt).inDays;
      final quote = PriceQuote(o.amount, ageDays: days < 0 ? 0 : days);
      final perPlace = out.putIfAbsent(placeId, () => {});
      final prev = perPlace[variantId];
      if (prev == null || quote.ageDays < prev.ageDays) {
        perPlace[variantId] = quote;
      }
    }
  });
  return out;
}

/// Plain-English text for a [BasketReason].
String describeReason(BasketReason r) => switch (r) {
  CheapestTotalReason() => 'Cheapest total',
  CoversAllReason(:final count) =>
    count == 1 ? 'Covers your 1 item' : 'Covers all $count items',
  CoversPartialReason(:final covered, :final total) =>
    'Prices only $covered of $total items',
  MissingItemsReason(:final count) =>
    count == 1 ? '1 item has no price here' : '$count items have no price here',
  SavesVersusNextReason(:final saving) =>
    'Saves ${saving.formatWithCode()} versus the next store',
  TiedReason() => 'Same total as another store; newer prices win',
  PricesAgeReason(:final days) =>
    days == 1 ? 'Oldest price is 1 day old' : 'Oldest price is $days days old',
  StalePricesReason(:final count, :final oldestDays) =>
    count == 1
        ? '1 price is stale (oldest $oldestDays days)'
        : '$count prices are stale (oldest $oldestDays days)',
  OnlyStoreReason() => 'Only store with prices for your items',
  SplitSavesReason(:final stores, :final saving) =>
    'Saves ${saving.formatWithCode()} across $stores stores',
  NotWorthSecondTripReason(:final saving, :final threshold) =>
    'Saves only ${saving.formatWithCode()}, under '
        '${threshold.formatWithCode()}: not worth a second trip',
};

/// Reasons that are warnings rather than good news.
bool isWarningReason(BasketReason r) =>
    r is CoversPartialReason ||
    r is MissingItemsReason ||
    r is StalePricesReason ||
    r is TiedReason ||
    r is NotWorthSecondTripReason;

/// Loads the latest price per place per product for the current basket and runs
/// [BasketOptimizer]. Re-runs when the basket or the places change.
final bestStoreProvider = FutureProvider.autoDispose<BestStoreState>((
  ref,
) async {
  final basket = ref.watch(basketProvider);
  final places = ref.watch(placesProvider).value ?? const [];
  final repo = ref.read(pricesRepositoryProvider);
  final (:lines, :skipped) = basketLines(basket);
  final offers = <String, List<PriceEntry>>{};
  for (final key in {for (final l in lines) l.key}) {
    offers[key] = await repo.currentOffersForVariant(key);
  }
  final prices = buildPriceMap(offers, DateTime.now());
  return BestStoreState(
    optimization: const BasketOptimizer().optimize(
      lines: lines,
      prices: prices,
    ),
    placeNames: {for (final p in places) p.id: p.name},
    itemNames: {for (final l in lines) l.key: l.label ?? 'Item'},
    skippedCount: skipped,
  );
});
