import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/use_cases/price_change.dart';
import '../../prices/view_models/user_location.dart';
import 'catalog_providers.dart';
import 'offer_rows.dart';

/// Which product page: the product and, optionally, which variant is selected.
typedef ProductDetailKey = ({String productId, String? variantId});

/// One entry of the history list.
class HistoryRow {
  const HistoryRow({
    required this.entry,
    required this.title,
    required this.change,
  });

  final PriceEntry entry;
  final String title;
  final PriceChange? change;
}

/// Everything the product page shows for one variant.
class ProductDetail {
  const ProductDetail({
    required this.product,
    required this.variant,
    required this.offers,
    required this.series,
    required this.history,
    required this.now,
    required this.staleDays,
  });

  final Product product;
  final Variant variant;
  final OffersView offers;
  final List<ChartSeries> series;

  /// Newest first.
  final List<HistoryRow> history;
  final DateTime now;
  final int staleDays;
}

/// Every price logged for a variant, newest first (live).
final variantHistoryProvider = StreamProvider.autoDispose
    .family<List<PriceEntry>, String>(
      (ref, variantId) =>
          ref.watch(pricesRepositoryProvider).watchHistoryForVariant(variantId),
    );

/// null data = the product does not exist (any more).
final productDetailProvider = Provider.autoDispose
    .family<AsyncValue<ProductDetail?>, ProductDetailKey>((ref, key) {
      final products = ref.watch(productsProvider);
      if (products.hasError) {
        return AsyncError(
          products.error!,
          products.stackTrace ?? StackTrace.current,
        );
      }
      final productList = products.value;
      if (productList == null) return const AsyncLoading();

      final product = productList
          .where((p) => p.id == key.productId)
          .firstOrNull;
      if (product == null || product.variants.isEmpty) {
        return const AsyncData(null);
      }
      final variant =
          product.variants.where((v) => v.id == key.variantId).firstOrNull ??
          product.variants.first;

      final history = ref.watch(variantHistoryProvider(variant.id));
      final staleDays = ref.watch(staleDaysProvider);
      final types = ref.watch(globalPriceTypesProvider);
      final places = ref.watch(placesByIdProvider);
      final location = ref.watch(userLocationProvider);
      final now = ref.watch(clockProvider)();

      if (history.hasError) {
        return AsyncError(
          history.error!,
          history.stackTrace ?? StackTrace.current,
        );
      }
      if (!history.hasValue || !staleDays.hasValue || !types.hasValue) {
        return const AsyncLoading();
      }

      final typeMap = {for (final t in types.value!) t.id: t};
      final entries = history.value!;
      final offers = buildOffersView(
        history: entries,
        variant: variant,
        places: places,
        types: typeMap,
        now: now,
        staleDays: staleDays.value!,
        from: location.value,
      );
      final changes = changesByEntry(entries);

      return AsyncData(
        ProductDetail(
          product: product,
          variant: variant,
          offers: offers,
          series: buildChartSeries(
            history: entries,
            places: places,
            types: typeMap,
            bestTitle: offers.best?.title,
          ),
          history: [
            for (final e in entries)
              HistoryRow(
                entry: e,
                title: storeTitle(e, places, typeMap),
                change: changes[e.id],
              ),
          ],
          now: now,
          staleDays: staleDays.value!,
        ),
      );
    });
