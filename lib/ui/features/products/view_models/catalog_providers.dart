import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/models/product.dart';

/// Source of "now" for the price features; tests override it with a fixed clock.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoriesRepositoryProvider).watchAll(),
);

final productsProvider = StreamProvider<List<Product>>(
  (ref) => ref.watch(productsRepositoryProvider).watchAll(),
);

/// One product by id (null while loading or when it does not exist / was deleted).
final productByIdProvider = Provider.family<Product?, String>((ref, id) {
  final products = ref.watch(productsProvider).value;
  if (products == null) return null;
  for (final p in products) {
    if (p.id == id) return p;
  }
  return null;
});

final allPlacesProvider = StreamProvider<List<Place>>(
  (ref) => ref.watch(placesRepositoryProvider).watchAll(),
);

final placesByIdProvider = Provider<Map<String, Place>>((ref) {
  final places = ref.watch(allPlacesProvider).value ?? const <Place>[];
  return {for (final p in places) p.id: p};
});

final globalPriceTypesProvider = StreamProvider<List<GlobalPriceType>>(
  (ref) => ref.watch(globalPriceTypesRepositoryProvider).watchAll(),
);

/// Days after which a price is "old" (setting, default 90).
final staleDaysProvider = StreamProvider<int>((ref) {
  return ref
      .watch(settingsRepositoryProvider)
      .watch(SettingKeys.staleDays)
      .map(
        (v) =>
            int.tryParse(v ?? '') ?? DriftSettingsRepository.defaultStaleDays,
      );
});
