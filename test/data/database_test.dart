import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/database/seed_data.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');

  group('schema + seed', () {
    test('schema version is 2', () => expect(db.schemaVersion, 2));

    test('seeds the starter lists on first open', () async {
      expect(await count('place_types'), seedPlaceTypes.length);
      expect(await count('payment_methods'), seedPaymentMethods.length);
      expect(await count('categories'), seedCategories.length);
      expect(await count('global_price_types'), seedGlobalPriceTypes.length);
    });

    test('seeded rows have stable UUIDs and are flagged built-in', () async {
      final supermarket =
          await (db.select(db.placeTypes)..where(
                (t) => t.id.equals(builtInId('place_type', 'supermarket')),
              ))
              .getSingle();
      expect(supermarket.name, 'Supermarket');
      expect(supermarket.isBuiltIn, isTrue);
      expect(supermarket.deletedAt, isNull);
      expect(
        builtInId('place_type', 'supermarket'),
        builtInId('place_type', 'supermarket'),
      );
      expect(
        builtInId('place_type', 'supermarket'),
        isNot(builtInId('category', 'supermarket')),
      );
    });

    test('all built-in ids are unique', () {
      final ids = {
        for (final t in seedPlaceTypes) builtInId('place_type', t.slug),
        for (final t in seedPaymentMethods) builtInId('payment_method', t.slug),
        for (final t in seedCategories) builtInId('category', t.slug),
        for (final t in seedGlobalPriceTypes)
          builtInId('global_price_type', t.slug),
      };
      expect(
        ids.length,
        seedPlaceTypes.length +
            seedPaymentMethods.length +
            seedCategories.length +
            seedGlobalPriceTypes.length,
      );
    });
  });

  group('constraints', () {
    final ts = DateTime(2026, 10, 16).millisecondsSinceEpoch;

    Future<void> insertEntry({
      String? variantId,
      String? menuOptionId,
      String? placeId,
      String? globalTypeId,
    }) => db
        .into(db.priceEntries)
        .insert(
          PriceEntriesCompanion.insert(
            id: newId(),
            variantId: Value(variantId),
            menuOptionId: Value(menuOptionId),
            placeId: Value(placeId),
            globalTypeId: Value(globalTypeId),
            amountMinor: 1000,
            seenAt: ts,
            createdAt: ts,
            updatedAt: ts,
          ),
        );

    test('a price entry needs exactly one of variant / menu option', () async {
      await expectLater(
        insertEntry(globalTypeId: builtInId('global_price_type', 'reference')),
        throwsA(anything),
      );
    });

    test('a global price needs a type', () async {
      final productId = newId();
      final variantId = newId();
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: productId,
              name: 'Milk',
              searchKey: 'milk',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      await db
          .into(db.variants)
          .insert(
            VariantsCompanion.insert(
              id: variantId,
              productId: productId,
              searchKey: 'milk',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      await expectLater(insertEntry(variantId: variantId), throwsA(anything));
      await insertEntry(
        variantId: variantId,
        globalTypeId: builtInId('global_price_type', 'reference'),
      );
      expect(await count('price_entries'), 1);
    });

    test('foreign keys are enforced', () async {
      await expectLater(
        db
            .into(db.places)
            .insert(
              PlacesCompanion.insert(
                id: newId(),
                name: 'X',
                typeId: 'missing',
                searchKey: 'x',
                createdAt: ts,
                updatedAt: ts,
              ),
            ),
        throwsA(anything),
      );
    });

    test('rating must be 1–5', () async {
      await expectLater(
        db
            .into(db.places)
            .insert(
              PlacesCompanion.insert(
                id: newId(),
                name: 'X',
                typeId: builtInId('place_type', 'cafe'),
                rating: const Value(6),
                searchKey: 'x',
                createdAt: ts,
                updatedAt: ts,
              ),
            ),
        throwsA(anything),
      );
    });
  });
}
