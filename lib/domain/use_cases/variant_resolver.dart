import '../models/product.dart';
import '../search/normalize_for_search.dart';

/// The product to save and the variant a new price belongs to.
class VariantResolution {
  const VariantResolution({
    required this.product,
    required this.variant,
    required this.changed,
  });

  /// The product with its variants brought up to date.
  final Product product;
  final Variant variant;

  /// True when the product needs saving (a variant was added or completed).
  final bool changed;
}

/// Decides which variant a logged price belongs to (D20: product + variants,
/// size through the size field):
///
/// * a variant with the same name and size is reused;
/// * a same-name variant with no size gets the size filled in;
/// * a same-name variant with a *different* size becomes a new variant (so 100 g
///   and 300 g keep separate histories);
/// * no size typed: the same-name variant is reused as it is;
/// * a barcode is attached to the chosen variant when it has none.
VariantResolution resolveVariant({
  required Product product,
  required String Function() newVariantId,
  String? variantName,
  double? sizeValue,
  SizeUnit? sizeUnit,
  String? barcode,
}) {
  final name = (variantName ?? '').trim().isEmpty ? null : variantName!.trim();
  final key = name == null ? null : normalizeForSearch(name);
  final hasSize = sizeValue != null && sizeUnit != null;
  final code = (barcode ?? '').trim().isEmpty ? null : barcode!.trim();

  bool sameName(Variant v) =>
      (v.name == null ? null : normalizeForSearch(v.name!)) == key;
  bool sameSize(Variant v) =>
      v.baseQuantity != null &&
      v.baseQuantity == sizeUnit?.baseQuantity(sizeValue ?? 0);

  final sameNamed = product.variants.where(sameName).toList();

  Variant? match;
  if (hasSize) {
    match = sameNamed.where(sameSize).firstOrNull;
    match ??= sameNamed.where((v) => v.sizeValue == null).firstOrNull;
  } else {
    match =
        sameNamed.where((v) => v.sizeValue == null).firstOrNull ??
        sameNamed.firstOrNull;
  }
  var variants = [...product.variants];
  Variant chosen;
  var changed = false;

  if (match == null) {
    chosen = Variant(
      id: newVariantId(),
      productId: product.id,
      name: name,
      barcode: code,
      sizeValue: hasSize ? sizeValue : null,
      sizeUnit: hasSize ? sizeUnit : null,
    );
    variants.add(chosen);
    changed = true;
  } else {
    final found = match;
    chosen = found;
    final needsSize = hasSize && found.sizeValue == null;
    final needsBarcode = code != null && found.barcode == null;
    final needsName = name != null && found.name == null;
    if (needsSize || needsBarcode || needsName) {
      final updated = Variant(
        id: found.id,
        productId: found.productId,
        name: found.name ?? name,
        barcode: found.barcode ?? code,
        sizeValue: needsSize ? sizeValue : found.sizeValue,
        sizeUnit: needsSize ? sizeUnit : found.sizeUnit,
      );
      chosen = updated;
      variants = [for (final v in variants) v.id == found.id ? updated : v];
      changed = true;
    }
  }

  return VariantResolution(
    product: Product(
      id: product.id,
      name: product.name,
      brand: product.brand,
      categoryId: product.categoryId,
      photoPath: product.photoPath,
      variants: variants,
    ),
    variant: chosen,
    changed: changed,
  );
}
