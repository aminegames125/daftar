import 'dart:convert';

import 'package:daftar/data/services/backup/backup_service.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/backup/csv.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedData(AppDatabase db) async {
  Future<void> sql(String s) => db.customStatement(s);
  const base = "created_at, updated_at";
  await sql(
    "INSERT INTO products (id, name, search_key, $base) VALUES ('p1', 'Lait, \"Delice\"', 'lait', 1, 1)",
  );
  await sql(
    "INSERT INTO variants (id, product_id, search_key, $base) VALUES ('v1', 'p1', 'lait', 1, 1)",
  );
  final typeId =
      (await db.customSelect('SELECT id FROM place_types LIMIT 1').getSingle())
          .read<String>('id');
  await sql(
    "INSERT INTO places (id, name, type_id, search_key, $base) VALUES ('pl1', 'Mg', '$typeId', 'mg', 1, 1)",
  );
  await sql(
    "INSERT INTO price_entries (id, variant_id, place_id, amount_minor, seen_at, $base) "
    "VALUES ('pe1', 'v1', 'pl1', 1284650, 1700000000000, 1, 1)",
  );
  await sql(
    "INSERT INTO accounts (id, name, kind, currency, icon_key, search_key, $base) "
    "VALUES ('a1', 'Cash', 'cash', 'tnd', 'wallet', 'cash', 1, 1)",
  );
  await sql(
    "INSERT INTO transactions (id, account_id, kind, amount_minor, currency, occurred_at, note, $base) "
    "VALUES ('t1', 'a1', 'expense', 4400, 'tnd', 1700000000000, 'Café', 1, 1)",
  );
}

Future<int> _count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM "$table"').getSingle())
        .read<int>('n');

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'export then restore into a fresh database round-trips exactly',
    () async {
      await _seedData(db);
      final json = await BackupService(db).exportJson();

      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      final summary = await BackupService(other).restoreJson(json);

      expect(summary.schemaVersion, db.schemaVersion);
      expect(await _count(other, 'price_entries'), 1);
      final pe = await other
          .customSelect('SELECT amount_minor FROM price_entries')
          .getSingle();
      expect(pe.read<int>('amount_minor'), 1284650);
      expect(
        await BackupService(other)
            .exportJson()
            .then((j) => jsonDecode(j)['tables']),
        jsonDecode(json)['tables'],
      );
    },
  );

  test('restore replaces existing data', () async {
    final json = await BackupService(db).exportJson();
    await _seedData(db);
    await BackupService(db).restoreJson(json);
    expect(await _count(db, 'price_entries'), 0);
    expect(await _count(db, 'place_types'), greaterThan(0));
  });

  test('rejects non-backup, newer-schema and unknown-table files without changing data', () async {
    await _seedData(db);
    final svc = BackupService(db);
    final good = jsonDecode(await svc.exportJson()) as Map<String, dynamic>;

    final bad = <String>[
      'not json',
      '{"hello": 1}',
      jsonEncode({...good, 'schemaVersion': db.schemaVersion + 1}),
      jsonEncode({
        ...good,
        'tables': {'evil; DROP TABLE x': []},
      }),
    ];
    for (final b in bad) {
      await expectLater(svc.restoreJson(b), throwsA(isA<BackupException>()));
    }
    expect(await _count(db, 'price_entries'), 1);
  });

  test(
    'a backup that fails inside the database leaves existing data intact',
    () async {
      await _seedData(db);
      final svc = BackupService(db);
      final doc = jsonDecode(await svc.exportJson()) as Map<String, dynamic>;
      // Dangling foreign key: price entry points at a place that is not there.
      final tables = doc['tables'] as Map<String, dynamic>;
      tables['places'] = [];
      await expectLater(
        svc.restoreJson(jsonEncode(doc)),
        throwsA(isA<BackupException>()),
      );
      expect(await _count(db, 'price_entries'), 1);
      expect(await _count(db, 'places'), 1);
      expect(await _count(db, 'transactions'), 1);
    },
  );

  test('an older schema version is accepted', () async {
    final doc = jsonDecode(
      await BackupService(db).exportJson(),
    ) as Map<String, dynamic>;
    doc['schemaVersion'] = 1;
    expect(BackupService(db).inspect(jsonEncode(doc)).schemaVersion, 1);
  });

  test(
    'price history CSV has exact decimals and escapes quotes/commas',
    () async {
      await _seedData(db);
      final csv = await BackupService(db).priceHistoryCsv();
      expect(csv.startsWith('﻿date,product'), isTrue);
      expect(csv, contains('"Lait, ""Delice"""'));
      expect(csv, contains(',1284.650,'));
      expect(csv, contains('2023-11-14T22:13:20.000Z'));
    },
  );

  test('transactions CSV lists account, kind and amount', () async {
    await _seedData(db);
    final csv = await BackupService(db).transactionsCsv();
    expect(csv, contains('Cash,expense,4.400,TND'));
    expect(csv, contains('Café'));
  });

  test('plainAmount is exact for both currencies and negatives', () {
    expect(plainAmount(4400, Currency.tnd), '4.400');
    expect(plainAmount(-5, Currency.tnd), '-0.005');
    expect(plainAmount(1999, Currency.usd), '19.99');
    expect(
      encodeCsv([
        ['a', 'b\nc'],
      ]),
      '﻿a,"b\nc"\r\n',
    );
  });
}
