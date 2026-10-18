import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../../domain/models/account.dart';
import '../../../domain/models/bill.dart';
import '../../../domain/models/debt.dart';
import '../../../domain/models/ids.dart';
import '../../../domain/models/lookups.dart';
import '../../../domain/models/money.dart';
import '../../../domain/models/photo.dart';
import '../../../domain/models/product.dart';
import 'seed_data.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Local SQLite database (DATA_MODEL). Offline-first and sync-ready: UUID keys,
/// `updated_at` on every write, soft deletes.
@DriftDatabase(
  tables: [
    Settings,
    PlaceTypes,
    Places,
    PaymentMethods,
    PlacePaymentMethods,
    PlaceTags,
    Categories,
    Products,
    Variants,
    MenuSections,
    MenuItems,
    MenuItemOptions,
    GlobalPriceTypes,
    PriceEntries,
    Photos,
    // Schema v2
    Accounts,
    Transactions,
    RateEntries,
    SavedLists,
    SavedListItems,
    Bills,
    BillPayments,
    Debts,
    DebtPayments,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database. Tests pass `NativeDatabase.memory()`.
  AppDatabase([QueryExecutor? executor, DateTime Function()? now])
    : _now = now ?? DateTime.now,
      super(executor ?? driftDatabase(name: 'daftar'));

  final DateTime Function() _now;

  /// Bump with every schema change and add a tested step to [migration].
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seed();
    },
    onUpgrade: (m, from, to) async {
      // v1 -> v2: accounts, saved lists, bills and debts. Purely additive.
      if (from < 2) {
        await m.createTable(accounts);
        await m.createTable(transactions);
        await m.createTable(rateEntries);
        await m.createTable(savedLists);
        await m.createTable(savedListItems);
        await m.createTable(bills);
        await m.createTable(billPayments);
        await m.createTable(debts);
        await m.createTable(debtPayments);
      }
      // Add `if (from < 3) { ... }` steps here, each with a migration test.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seed() async {
    final nowMs = _now().toUtc().millisecondsSinceEpoch;

    await batch((b) {
      b.insertAll(placeTypes, [
        for (final (i, t) in seedPlaceTypes.indexed)
          PlaceTypesCompanion.insert(
            id: builtInId('place_type', t.slug),
            name: t.name,
            iconKey: t.iconKey,
            kind: t.kind,
            sortOrder: Value(i),
            isBuiltIn: const Value(true),
            createdAt: nowMs,
            updatedAt: nowMs,
          ),
      ]);
      b.insertAll(paymentMethods, [
        for (final (i, m) in seedPaymentMethods.indexed)
          PaymentMethodsCompanion.insert(
            id: builtInId('payment_method', m.slug),
            name: m.name,
            iconKey: m.iconKey,
            sortOrder: Value(i),
            isBuiltIn: const Value(true),
            createdAt: nowMs,
            updatedAt: nowMs,
          ),
      ]);
      b.insertAll(categories, [
        for (final (i, c) in seedCategories.indexed)
          CategoriesCompanion.insert(
            id: builtInId('category', c.slug),
            name: c.name,
            iconKey: c.iconKey,
            sortOrder: Value(i),
            isBuiltIn: const Value(true),
            createdAt: nowMs,
            updatedAt: nowMs,
          ),
      ]);
      b.insertAll(globalPriceTypes, [
        for (final (i, g) in seedGlobalPriceTypes.indexed)
          GlobalPriceTypesCompanion.insert(
            id: builtInId('global_price_type', g.slug),
            name: g.name,
            sortOrder: Value(i),
            isBuiltIn: const Value(true),
            createdAt: nowMs,
            updatedAt: nowMs,
          ),
      ]);
    });
  }
}
