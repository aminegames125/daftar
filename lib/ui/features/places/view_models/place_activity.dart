import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/price_entry.dart';

/// One logged price at a place, with what it was for.
class PlaceActivity {
  const PlaceActivity({
    required this.entry,
    required this.title,
    this.subtitle,
    this.productId,
    this.menuItemId,
  });

  final PriceEntry entry;

  /// Product name or menu item name.
  final String title;

  /// Variant name or option name ("Oreo", "L").
  final String? subtitle;
  final String? productId;
  final String? menuItemId;

  /// What the price was logged against (variant or menu option).
  String get targetId => entry.variantId ?? entry.menuOptionId!;
}

/// The newest entry per product variant / menu option, newest first.
/// Input must already be sorted newest first.
List<PlaceActivity> latestPerTarget(List<PlaceActivity> newestFirst) {
  final seen = <String>{};
  return [
    for (final a in newestFirst)
      if (seen.add(a.targetId)) a,
  ];
}

/// Every price logged at [placeId] (products and menu), newest first. In-memory
/// join over the repositories (data is small); refresh with `ref.invalidate`
/// after logging a price.
final placeActivityProvider = FutureProvider.autoDispose
    .family<List<PlaceActivity>, String>((ref, placeId) async {
      final products = await ref
          .read(productsRepositoryProvider)
          .watchAll()
          .first;
      final prices = ref.read(pricesRepositoryProvider);
      final menuItems = await ref
          .read(menuRepositoryProvider)
          .watchItems(placeId)
          .first;
      final all = <PlaceActivity>[];

      for (final product in products) {
        for (final variant in product.variants) {
          final history = await prices.watchHistoryForVariant(variant.id).first;
          for (final entry in history) {
            if (entry.placeId != placeId) continue;
            all.add(
              PlaceActivity(
                entry: entry,
                title: product.name,
                subtitle: variant.name,
                productId: product.id,
              ),
            );
          }
        }
      }
      for (final item in menuItems) {
        for (final option in item.options) {
          final history = await prices
              .watchHistoryForMenuOption(option.id)
              .first;
          for (final entry in history) {
            if (entry.placeId != placeId) continue;
            all.add(
              PlaceActivity(
                entry: entry,
                title: item.name,
                subtitle: option.name,
                menuItemId: item.id,
              ),
            );
          }
        }
      }
      all.sort((a, b) => b.entry.seenAt.compareTo(a.entry.seenAt));
      return all;
    });

/// Prices at this place that belong to products (the "Products" tab of a shop).
final placeProductPricesProvider = Provider.autoDispose
    .family<AsyncValue<List<PlaceActivity>>, String>((ref, placeId) {
      return ref
          .watch(placeActivityProvider(placeId))
          .whenData(
            (all) => latestPerTarget([
              for (final a in all)
                if (a.productId != null) a,
            ]),
          );
    });

/// Days after which a price counts as old (settings, default 90).
final staleDaysProvider = FutureProvider<int>(
  (ref) => ref.read(settingsRepositoryProvider).getStaleDays(),
);
