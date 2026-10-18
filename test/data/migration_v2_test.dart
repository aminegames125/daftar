import 'dart:io';

import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _v2Tables = [
  'debt_payments',
  'debts',
  'bill_payments',
  'bills',
  'saved_list_items',
  'saved_lists',
  'rate_entries',
  'transactions',
  'accounts',
];

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('daftar_migration_');
    file = File('${dir.path}/daftar.sqlite');
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold the file for a moment; the OS cleans the temp dir.
    }
  });

  /// Builds a database file that looks exactly like schema v1: the v2 tables
  /// are dropped and `user_version` is 1.
  Future<void> createV1File() async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get(); // force creation + seed
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p1',
            name: 'Milk',
            categoryId: Value(builtInId('category', 'food')),
            searchKey: 'milk',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    for (final t in _v2Tables) {
      await db.customStatement('DROP TABLE $t');
    }
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();
  }

  test(
    'v1 database upgrades to v2 keeping data and adding the new tables',
    () async {
      await createV1File();

      final db = AppDatabase(NativeDatabase(file));

      expect(db.schemaVersion, 2);
      for (final t in _v2Tables) {
        final rows = await db
            .customSelect('SELECT COUNT(*) AS c FROM $t')
            .getSingle();
        expect(rows.read<int>('c'), 0, reason: t);
      }
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 2);

      // Old data survived and was not re-seeded.
      final products = await db.select(db.products).get();
      expect(products.map((p) => p.id), ['p1']);
      final categories = await db
          .customSelect('SELECT COUNT(*) AS c FROM categories')
          .getSingle();
      expect(categories.read<int>('c'), greaterThan(0));

      // The upgraded tables are usable, including their foreign keys.
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'a1',
              name: 'Cash',
              kind: AccountKind.cash,
              currency: Currency.tnd,
              iconKey: 'cash',
              searchKey: 'cash',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      expect((await db.select(db.accounts).get()).single.id, 'a1');
      expect(
        (await db.customSelect('PRAGMA foreign_key_check').get()),
        isEmpty,
      );
      await db.close();
    },
  );

  test(
    'migration is idempotent: reopening a v2 file changes nothing',
    () async {
      await createV1File();
      var db = AppDatabase(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      expect((await db.select(db.products).get()).length, 1);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 2);
      await db.close();
    },
  );
}
