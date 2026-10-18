import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/menu.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/product.dart';
import 'home_summary.dart';

// Home reads small, personal data sets, so it combines the existing repository
// streams (one per variant / menu option) instead of needing a dedicated query.
// All of them are live: logging a price updates Home immediately.

final _placesProvider = StreamProvider<List<Place>>(
  (ref) => ref.watch(placesRepositoryProvider).watchAll(),
);

final _productsProvider = StreamProvider<List<Product>>(
  (ref) => ref.watch(productsRepositoryProvider).watchAll(),
);

final _globalTypesProvider = StreamProvider<List<GlobalPriceType>>(
  (ref) => ref.watch(globalPriceTypesRepositoryProvider).watchAll(),
);

final _menuItemsProvider = StreamProvider.family<List<MenuItem>, String>(
  (ref, placeId) => ref.watch(menuRepositoryProvider).watchItems(placeId),
);

final _variantHistoryProvider = StreamProvider.family<List<PriceEntry>, String>(
  (ref, variantId) =>
      ref.watch(pricesRepositoryProvider).watchHistoryForVariant(variantId),
);

final _optionHistoryProvider = StreamProvider.family<List<PriceEntry>, String>(
  (ref, optionId) =>
      ref.watch(pricesRepositoryProvider).watchHistoryForMenuOption(optionId),
);

/// Counts, latest price and the Recent list for Home.
///
/// Loading until every stream has produced its first value; if the database
/// fails the error is passed on and Home shows its empty state.
final homeSummaryProvider = Provider<AsyncValue<HomeSummary>>((ref) {
  final places = ref.watch(_placesProvider);
  final products = ref.watch(_productsProvider);
  final types = ref.watch(_globalTypesProvider);

  for (final base in [places, products, types]) {
    if (base.hasError) {
      return AsyncError(base.error!, base.stackTrace ?? StackTrace.empty);
    }
  }
  if (places.isLoading || products.isLoading || types.isLoading) {
    return const AsyncLoading();
  }

  final placeList = places.requireValue;
  final productList = products.requireValue;

  final menuItemsByPlace = <String, List<MenuItem>>{};
  var loading = false;
  for (final place in placeList) {
    final items = ref.watch(_menuItemsProvider(place.id));
    loading |= items.isLoading;
    menuItemsByPlace[place.id] = items.value ?? const [];
  }

  final historyByVariant = <String, List<PriceEntry>>{};
  for (final product in productList) {
    for (final variant in product.variants) {
      final history = ref.watch(_variantHistoryProvider(variant.id));
      loading |= history.isLoading;
      historyByVariant[variant.id] = history.value ?? const [];
    }
  }

  final historyByOption = <String, List<PriceEntry>>{};
  for (final items in menuItemsByPlace.values) {
    for (final item in items) {
      for (final option in item.options) {
        final history = ref.watch(_optionHistoryProvider(option.id));
        loading |= history.isLoading;
        historyByOption[option.id] = history.value ?? const [];
      }
    }
  }

  if (loading) return const AsyncLoading();

  return AsyncData(
    buildHomeSummary(
      places: placeList,
      products: productList,
      menuItemsByPlace: menuItemsByPlace,
      historyByVariant: historyByVariant,
      historyByOption: historyByOption,
      globalTypes: types.requireValue,
    ),
  );
});
