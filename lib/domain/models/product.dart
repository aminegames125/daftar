/// Units a product size can be given in. Sizes are normalised to a base
/// quantity (g, ml or pieces) so offers of different pack sizes can be compared.
enum SizeUnit {
  g(dimension: SizeDimension.mass, toBase: 1),
  kg(dimension: SizeDimension.mass, toBase: 1000),
  ml(dimension: SizeDimension.volume, toBase: 1),
  l(dimension: SizeDimension.volume, toBase: 1000),
  pc(dimension: SizeDimension.count, toBase: 1);

  const SizeUnit({required this.dimension, required this.toBase});

  final SizeDimension dimension;
  final int toBase;

  /// 0.75 l → 750 ml, 1.5 kg → 1500 g.
  int baseQuantity(double value) => (value * toBase).round();
}

enum SizeDimension { mass, volume, count }

/// One buyable version of a product (Milka → Oreo / Noisette). A product with no
/// variants of its own has a single default variant with a `null` name.
class Variant {
  const Variant({
    required this.id,
    required this.productId,
    this.name,
    this.barcode,
    this.sizeValue,
    this.sizeUnit,
  });

  final String id;
  final String productId;
  final String? name;
  final String? barcode;
  final double? sizeValue;
  final SizeUnit? sizeUnit;

  /// Size in g, ml or pieces; null when no size was given.
  int? get baseQuantity {
    final value = sizeValue;
    final unit = sizeUnit;
    if (value == null || unit == null) return null;
    return unit.baseQuantity(value);
  }
}

class Product {
  const Product({
    required this.id,
    required this.name,
    this.brand,
    this.categoryId,
    this.photoPath,
    this.variants = const [],
  });

  final String id;
  final String name;
  final String? brand;
  final String? categoryId;
  final String? photoPath;
  final List<Variant> variants;
}
