import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../domain/models/ids.dart';
import '../../domain/models/product.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class ProductsRepository {
  /// All products with their variants, A→Z.
  Stream<List<Product>> watchAll();
  Future<Product?> get(String id);

  /// The product that owns a variant with this barcode, if any.
  Future<Product?> findByBarcode(String barcode);

  /// Insert or update the product and sync its variants: variants missing from
  /// [Product.variants] are soft-deleted. A product with no variants gets one
  /// default variant so prices always have something to attach to.
  Future<void> save(Product product);

  /// Soft delete the product and its variants. Price history stays.
  Future<void> delete(String id);
}

class DriftProductsRepository implements ProductsRepository {
  DriftProductsRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  @override
  Stream<List<Product>> watchAll() {
    final query = _db.select(_db.products)
      ..where((p) => p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.asc(p.searchKey)]);
    return query.watch().asyncMap(_withVariants);
  }

  @override
  Future<Product?> get(String id) async {
    final rows = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(id) & p.deletedAt.isNull())).get();
    return (await _withVariants(rows)).firstOrNull;
  }

  @override
  Future<Product?> findByBarcode(String barcode) async {
    final variant =
        await (_db.select(_db.variants)
              ..where((v) => v.barcode.equals(barcode) & v.deletedAt.isNull()))
            .getSingleOrNull();
    return variant == null ? null : get(variant.productId);
  }

  Future<List<Product>> _withVariants(List<ProductRow> rows) async {
    if (rows.isEmpty) return const [];
    final variants =
        await (_db.select(_db.variants)
              ..where(
                (v) =>
                    v.productId.isIn(rows.map((r) => r.id).toList()) &
                    v.deletedAt.isNull(),
              )
              ..orderBy([(v) => OrderingTerm.asc(v.createdAt)]))
            .get();
    final byProduct = variants.groupListsBy((v) => v.productId);
    return [
      for (final r in rows)
        Product(
          id: r.id,
          name: r.name,
          brand: r.brand,
          categoryId: r.categoryId,
          photoPath: r.photoPath,
          variants: [
            for (final v in byProduct[r.id] ?? const <VariantRow>[])
              Variant(
                id: v.id,
                productId: v.productId,
                name: v.name,
                barcode: v.barcode,
                sizeValue: v.sizeValue,
                sizeUnit: v.sizeUnit,
              ),
          ],
        ),
    ];
  }

  @override
  Future<void> save(Product product) => _db.transaction(() async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(product.id))).getSingleOrNull();
    final values = ProductsCompanion(
      name: Value(product.name),
      brand: Value(product.brand),
      categoryId: Value(product.categoryId),
      photoPath: Value(product.photoPath),
      searchKey: Value(searchKeyOf([product.name, product.brand])),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.products)
          .insert(
            values.copyWith(id: Value(product.id), createdAt: Value(now)),
          );
    } else {
      await (_db.update(
        _db.products,
      )..where((p) => p.id.equals(product.id))).write(values);
    }

    final variants = product.variants.isEmpty
        ? [
            Variant(
              id: builtInId('default_variant', product.id),
              productId: product.id,
            ),
          ]
        : product.variants;
    final keepIds = variants.map((v) => v.id).toList();
    await (_db.update(_db.variants)..where(
          (v) =>
              v.productId.equals(product.id) &
              v.id.isNotIn(keepIds) &
              v.deletedAt.isNull(),
        ))
        .write(VariantsCompanion(deletedAt: Value(now), updatedAt: Value(now)));

    for (final variant in variants) {
      final existingVariant = await (_db.select(
        _db.variants,
      )..where((v) => v.id.equals(variant.id))).getSingleOrNull();
      final variantValues = VariantsCompanion(
        productId: Value(product.id),
        name: Value(variant.name),
        barcode: Value(variant.barcode),
        sizeValue: Value(variant.sizeValue),
        sizeUnit: Value(variant.sizeUnit),
        baseQuantity: Value(variant.baseQuantity),
        searchKey: Value(
          searchKeyOf([
            product.name,
            product.brand,
            variant.name,
            variant.barcode,
          ]),
        ),
        updatedAt: Value(now),
        deletedAt: const Value(null),
      );
      if (existingVariant == null) {
        await _db
            .into(_db.variants)
            .insert(
              variantValues.copyWith(
                id: Value(variant.id),
                createdAt: Value(now),
              ),
            );
      } else {
        await (_db.update(
          _db.variants,
        )..where((v) => v.id.equals(variant.id))).write(variantValues);
      }
    }
  });

  @override
  Future<void> delete(String id) => _db.transaction(() async {
    final now = toEpochMs(_now());
    await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (_db.update(_db.variants)
          ..where((v) => v.productId.equals(id) & v.deletedAt.isNull()))
        .write(VariantsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  });
}
