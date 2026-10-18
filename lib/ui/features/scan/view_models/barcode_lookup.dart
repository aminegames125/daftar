import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/repositories/products_repository.dart';
import '../../../../data/services/open_food_facts_provider.dart';
import '../../../../data/services/open_food_facts_service.dart';
import '../../../../domain/models/product.dart';

/// What a scanned barcode turned out to be.
sealed class BarcodeMatch {
  const BarcodeMatch(this.barcode);
  final String barcode;
}

/// Already in the local database (offline-first: checked before the network).
class LocalMatch extends BarcodeMatch {
  const LocalMatch(super.barcode, this.product, this.variant);
  final Product product;
  final Variant variant;
}

/// Not stored yet, but Open Food Facts knows it.
class OffMatch extends BarcodeMatch {
  const OffMatch(super.barcode, this.product);
  final OffProduct product;
}

/// Unknown everywhere (or no network): the user types the product in.
class NoMatch extends BarcodeMatch {
  const NoMatch(super.barcode, {required this.offline});

  /// True when Open Food Facts could not be reached, so "not found" is not certain.
  final bool offline;
}

/// Finds a barcode in the local database first, then on Open Food Facts.
class BarcodeLookup {
  BarcodeLookup(this._products, this._off);

  final ProductsRepository _products;
  final OpenFoodFactsService _off;

  Future<BarcodeMatch> lookup(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    final local = await _products.findByBarcode(barcode);
    if (local != null) {
      final variant = local.variants.firstWhere(
        (v) => v.barcode == barcode,
        orElse: () => local.variants.first,
      );
      return LocalMatch(barcode, local, variant);
    }
    return switch (await _off.lookup(barcode)) {
      OffFound(:final product) => OffMatch(barcode, product),
      OffNotFound() => NoMatch(barcode, offline: false),
      OffUnavailable() => NoMatch(barcode, offline: true),
    };
  }
}

final barcodeLookupProvider = Provider<BarcodeLookup>(
  (ref) => BarcodeLookup(
    ref.watch(productsRepositoryProvider),
    ref.watch(openFoodFactsServiceProvider),
  ),
);
