import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/database/seed_data.dart';
import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/ui/features/settings/view_models/managed_lists.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  ManagedList list(ManagedListKind kind) =>
      container.read(managedListProvider(kind));
  Future<List<ManagedItem>> items(ManagedListKind kind) =>
      list(kind).watch().first;

  group('every list', () {
    for (final kind in ManagedListKind.values) {
      group(kind.title, () {
        test('starts with its starter rows, all built in', () async {
          final rows = await items(kind);
          expect(rows, hasLength(list(kind).starterCount));
          expect(rows.every((r) => r.isBuiltIn), isTrue);
        });

        test('add puts a custom row at the end', () async {
          final before = await items(kind);
          await list(kind).add('  Open   air  market ');
          final rows = await items(kind);
          expect(rows, hasLength(before.length + 1));
          expect(rows.last.name, 'Open air market');
          expect(rows.last.isBuiltIn, isFalse);
        });

        test(
          'a starter row can be renamed and keeps its id and built-in flag',
          () async {
            final first = (await items(kind)).first;
            await list(kind).rename(first, 'Renamed');
            final after = (await items(kind))
                .firstWhere((r) => r.id == first.id);
            expect(after.name, 'Renamed');
            expect(after.isBuiltIn, isTrue);
          },
        );

        test('hide removes the row from the list, restore brings only missing starters back', () async {
          final rows = await items(kind);
          await list(kind).rename(rows[1], 'Kept rename');
          await list(kind).hide(rows[0]);

          var now = await items(kind);
          expect(now, hasLength(rows.length - 1));
          expect(now.any((r) => r.id == rows[0].id), isFalse);

          final restored = await list(kind).restoreStarters(now);
          expect(restored, 1);
          now = await items(kind);
          expect(now, hasLength(rows.length));
          expect(
            now.firstWhere((r) => r.id == rows[1].id).name,
            'Kept rename',
          ); // untouched
          expect(await list(kind).restoreStarters(now), 0);
        });

        test('reorder saves the new order', () async {
          final rows = await items(kind);
          final reversed = rows.reversed.toList();
          await list(kind).reorder(reversed);
          expect(
            (await items(kind)).map((r) => r.id),
            reversed.map((r) => r.id),
          );
        });
      });
    }
  });

  test(
    'place types: new type keeps the chosen kind, starters expose theirs',
    () async {
      final l = list(ManagedListKind.placeTypes);
      await l.add('Market', placeKind: PlaceKind.shop);
      await l.add('Barber', placeKind: PlaceKind.venue);
      final rows = await items(ManagedListKind.placeTypes);
      expect(
        (rows.firstWhere((r) => r.name == 'Market').source! as PlaceType).kind,
        PlaceKind.shop,
      );
      expect(
        (rows.firstWhere((r) => r.name == 'Barber').source! as PlaceType).kind,
        PlaceKind.venue,
      );
      expect(
        rows.firstWhere((r) => r.name == 'Café').detail,
        startsWith('Venue'),
      );
    },
  );

  test('starter counts match the seed data', () {
    expect(
      list(ManagedListKind.placeTypes).starterCount,
      seedPlaceTypes.length,
    );
    expect(
      list(ManagedListKind.categories).starterCount,
      seedCategories.length,
    );
  });
}
