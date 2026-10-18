import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/use_cases/best_offer_scorer.dart';
import '../../../../domain/use_cases/offer_inputs.dart';
import '../../../../domain/use_cases/price_change.dart';

/// One current offer of a variant, ready to draw.
class OfferRow {
  const OfferRow({
    required this.entry,
    required this.title,
    required this.place,
    required this.distanceKm,
    required this.ageDays,
    required this.isStale,
    required this.isBest,
    required this.change,
    required this.unitPrice,
    this.variant,
  });

  final PriceEntry entry;

  /// The place name, or the global price type ("Reference price").
  final String title;
  final Place? place;
  final double? distanceKm;
  final int ageDays;

  /// Older than the stale threshold: drawn at 40% opacity with "old".
  final bool isStale;
  final bool isBest;

  /// Versus the previous price at the same store.
  final PriceChange? change;

  /// "per 100 g" price when offers were compared by unit.
  final Money? unitPrice;

  /// The variant this price is for (matters when several variants are compared).
  final Variant? variant;
}

/// The current offers of one variant plus the verdict.
class OffersView {
  const OffersView({
    required this.rows,
    required this.basis,
    required this.reasons,
  });

  /// Best first.
  final List<OfferRow> rows;
  final PriceBasis basis;

  /// Why the best row won.
  final List<String> reasons;

  OfferRow? get best => rows.isEmpty ? null : rows.first;
  static const empty = OffersView(rows: [], basis: PriceBasis.raw, reasons: []);
}

String storeTitle(
  PriceEntry entry,
  Map<String, Place> places,
  Map<String, GlobalPriceType> types,
) {
  final placeId = entry.placeId;
  if (placeId != null) return places[placeId]?.name ?? 'Removed place';
  return types[entry.globalTypeId]?.name ?? 'Global price';
}

/// Current offers of [variant], scored (DATA_MODEL § 7).
OffersView buildOffersView({
  required Iterable<PriceEntry> history,
  required Variant variant,
  required Map<String, Place> places,
  required Map<String, GlobalPriceType> types,
  required DateTime now,
  required int staleDays,
  GeoPoint? from,
}) => buildMultiVariantOffersView(
  historyByVariant: {variant: history},
  places: places,
  types: types,
  now: now,
  staleDays: staleDays,
  from: from,
);

/// Offers of several variants of one product, scored together: when every variant
/// has a size in the same dimension the comparison is by unit price, so a 300 g
/// bar can beat a 100 g one.
OffersView buildMultiVariantOffersView({
  required Map<Variant, Iterable<PriceEntry>> historyByVariant,
  required Map<String, Place> places,
  required Map<String, GlobalPriceType> types,
  required DateTime now,
  required int staleDays,
  GeoPoint? from,
}) {
  final variantById = {for (final v in historyByVariant.keys) v.id: v};
  final inputs = [
    for (final MapEntry(key: variant, value: history)
        in historyByVariant.entries)
      for (final e in history)
        offerInputFor(e, variant: variant, place: places[e.placeId]),
  ];
  final result = BestOfferScorer(staleDays: staleDays)
      .score(inputs, now: now, from: from);
  if (result == null) return OffersView.empty;

  final changes = <String, PriceChange>{
    for (final history in historyByVariant.values) ...changesByEntry(history),
  };
  return OffersView(
    basis: result.basis,
    reasons: result.reasons,
    rows: [
      for (var i = 0; i < result.ranked.length; i++)
        OfferRow(
          entry: result.ranked[i].entry,
          title: storeTitle(result.ranked[i].entry, places, types),
          place: places[result.ranked[i].entry.placeId],
          distanceKm: result.ranked[i].distanceKm,
          ageDays: result.ranked[i].ageDays,
          isStale: result.ranked[i].isStale,
          isBest: i == 0,
          change: changes[result.ranked[i].entry.id],
          unitPrice: result.ranked[i].unitPrice,
          variant: variantById[result.ranked[i].entry.variantId],
        ),
    ],
  );
}

/// Offers for one menu option across venues ("capucin" at every café), scored
/// like product offers. Menu options have no size, so the comparison is by raw price.
OffersView buildMenuOffersView({
  required Iterable<PriceEntry> entries,
  required Map<String, Place> places,
  required Map<String, GlobalPriceType> types,
  required DateTime now,
  required int staleDays,
  GeoPoint? from,
}) {
  final list = entries.toList();
  final inputs = [
    for (final e in list) offerInputFor(e, place: places[e.placeId]),
  ];
  final result = BestOfferScorer(staleDays: staleDays)
      .score(inputs, now: now, from: from);
  if (result == null) return OffersView.empty;
  final changes = changesByEntry(list);
  return OffersView(
    basis: result.basis,
    reasons: result.reasons,
    rows: [
      for (var i = 0; i < result.ranked.length; i++)
        OfferRow(
          entry: result.ranked[i].entry,
          title: storeTitle(result.ranked[i].entry, places, types),
          place: places[result.ranked[i].entry.placeId],
          distanceKm: result.ranked[i].distanceKm,
          ageDays: result.ranked[i].ageDays,
          isStale: result.ranked[i].isStale,
          isBest: i == 0,
          change: changes[result.ranked[i].entry.id],
          unitPrice: null,
        ),
    ],
  );
}

/// A point of the price chart. [value] is TND as a plain number, *only* for
/// drawing (all money logic stays in [Money]).
class ChartPoint {
  const ChartPoint(this.at, this.value);
  final DateTime at;
  final double value;
}

/// One line of the chart: the history at one store.
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.points,
    required this.isBest,
  });
  final String label;

  /// Oldest first.
  final List<ChartPoint> points;
  final bool isBest;
}

/// A line per store (most-priced stores first, at most [maxSeries]).
List<ChartSeries> buildChartSeries({
  required Iterable<PriceEntry> history,
  required Map<String, Place> places,
  required Map<String, GlobalPriceType> types,
  String? bestTitle,
  int maxSeries = 5,
}) {
  final byStore = <String, List<PriceEntry>>{};
  for (final e in history) {
    byStore
        .putIfAbsent(e.placeId ?? 'global:${e.globalTypeId}', () => [])
        .add(e);
  }
  final series = [
    for (final entries in byStore.values)
      ChartSeries(
        label: storeTitle(entries.first, places, types),
        isBest: storeTitle(entries.first, places, types) == bestTitle,
        points: [
          for (final e
              in (entries..sort((a, b) => a.seenAt.compareTo(b.seenAt))))
            ChartPoint(e.seenAt, e.amount.minor / e.amount.currency.unit),
        ],
      ),
  ]..sort((a, b) => b.points.length.compareTo(a.points.length));
  return series.take(maxSeries).toList();
}
