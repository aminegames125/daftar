import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../domain/models/ids.dart';
import '../../domain/models/menu.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class MenuRepository {
  Stream<List<MenuSection>> watchSections(String placeId);

  /// Items of a venue with their options, in menu order.
  Stream<List<MenuItem>> watchItems(String placeId);

  Future<void> saveSection(MenuSection section);

  /// Soft delete; its items stay but lose the section.
  Future<void> deleteSection(String id);

  /// Insert or update an item and sync its options: options missing from
  /// [MenuItem.options] are soft-deleted. An item with no options gets one
  /// single-price option so prices always have something to attach to.
  Future<void> saveItem(MenuItem item);

  /// Soft delete the item and its options. Price history stays.
  Future<void> deleteItem(String id);

  Future<void> setUsual(String itemId, {required bool isUsual});
}

class DriftMenuRepository implements MenuRepository {
  DriftMenuRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  @override
  Stream<List<MenuSection>> watchSections(String placeId) {
    final query = _db.select(_db.menuSections)
      ..where((s) => s.placeId.equals(placeId) & s.deletedAt.isNull())
      ..orderBy([
        (s) => OrderingTerm.asc(s.sortOrder),
        (s) => OrderingTerm.asc(s.createdAt),
      ]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          MenuSection(
            id: r.id,
            placeId: r.placeId,
            name: r.name,
            sortOrder: r.sortOrder,
          ),
      ],
    );
  }

  @override
  Stream<List<MenuItem>> watchItems(String placeId) {
    final query = _db.select(_db.menuItems)
      ..where((i) => i.placeId.equals(placeId) & i.deletedAt.isNull())
      ..orderBy([
        (i) => OrderingTerm.asc(i.sortOrder),
        (i) => OrderingTerm.asc(i.createdAt),
      ]);
    return query.watch().asyncMap((rows) async {
      if (rows.isEmpty) return const <MenuItem>[];
      final options =
          await (_db.select(_db.menuItemOptions)
                ..where(
                  (o) =>
                      o.menuItemId.isIn(rows.map((r) => r.id).toList()) &
                      o.deletedAt.isNull(),
                )
                ..orderBy([
                  (o) => OrderingTerm.asc(o.sortOrder),
                  (o) => OrderingTerm.asc(o.createdAt),
                ]))
              .get();
      final byItem = options.groupListsBy((o) => o.menuItemId);
      return [
        for (final r in rows)
          MenuItem(
            id: r.id,
            placeId: r.placeId,
            sectionId: r.sectionId,
            name: r.name,
            isUsual: r.isUsual,
            sortOrder: r.sortOrder,
            options: [
              for (final o in byItem[r.id] ?? const <MenuItemOptionRow>[])
                MenuItemOption(
                  id: o.id,
                  menuItemId: o.menuItemId,
                  name: o.name,
                  sortOrder: o.sortOrder,
                ),
            ],
          ),
      ];
    });
  }

  @override
  Future<void> saveSection(MenuSection section) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.menuSections,
    )..where((s) => s.id.equals(section.id))).getSingleOrNull();
    final values = MenuSectionsCompanion(
      placeId: Value(section.placeId),
      name: Value(section.name),
      sortOrder: Value(section.sortOrder),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.menuSections)
          .insert(
            values.copyWith(id: Value(section.id), createdAt: Value(now)),
          );
    } else {
      await (_db.update(
        _db.menuSections,
      )..where((s) => s.id.equals(section.id))).write(values);
    }
  }

  @override
  Future<void> deleteSection(String id) => _db.transaction(() async {
    final now = toEpochMs(_now());
    await (_db.update(_db.menuSections)..where((s) => s.id.equals(id))).write(
      MenuSectionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (_db.update(
      _db.menuItems,
    )..where((i) => i.sectionId.equals(id))).write(
      MenuItemsCompanion(sectionId: const Value(null), updatedAt: Value(now)),
    );
  });

  @override
  Future<void> saveItem(MenuItem item) => _db.transaction(() async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.menuItems,
    )..where((i) => i.id.equals(item.id))).getSingleOrNull();
    final values = MenuItemsCompanion(
      placeId: Value(item.placeId),
      sectionId: Value(item.sectionId),
      name: Value(item.name),
      isUsual: Value(item.isUsual),
      sortOrder: Value(item.sortOrder),
      searchKey: Value(searchKeyOf([item.name])),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.menuItems)
          .insert(values.copyWith(id: Value(item.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.menuItems,
      )..where((i) => i.id.equals(item.id))).write(values);
    }

    final options = item.options.isEmpty
        ? [
            MenuItemOption(
              id: builtInId('default_option', item.id),
              menuItemId: item.id,
            ),
          ]
        : item.options;
    await (_db.update(_db.menuItemOptions)..where(
          (o) =>
              o.menuItemId.equals(item.id) &
              o.id.isNotIn(options.map((o) => o.id).toList()) &
              o.deletedAt.isNull(),
        ))
        .write(
          MenuItemOptionsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    for (final option in options) {
      final existingOption = await (_db.select(
        _db.menuItemOptions,
      )..where((o) => o.id.equals(option.id))).getSingleOrNull();
      final optionValues = MenuItemOptionsCompanion(
        menuItemId: Value(item.id),
        name: Value(option.name),
        sortOrder: Value(option.sortOrder),
        updatedAt: Value(now),
        deletedAt: const Value(null),
      );
      if (existingOption == null) {
        await _db
            .into(_db.menuItemOptions)
            .insert(
              optionValues.copyWith(
                id: Value(option.id),
                createdAt: Value(now),
              ),
            );
      } else {
        await (_db.update(
          _db.menuItemOptions,
        )..where((o) => o.id.equals(option.id))).write(optionValues);
      }
    }
  });

  @override
  Future<void> deleteItem(String id) => _db.transaction(() async {
    final now = toEpochMs(_now());
    await (_db.update(_db.menuItems)..where((i) => i.id.equals(id))).write(
      MenuItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await (_db.update(
      _db.menuItemOptions,
    )..where((o) => o.menuItemId.equals(id) & o.deletedAt.isNull())).write(
      MenuItemOptionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  });

  @override
  Future<void> setUsual(String itemId, {required bool isUsual}) =>
      (_db.update(_db.menuItems)..where((i) => i.id.equals(itemId))).write(
        MenuItemsCompanion(
          isUsual: Value(isUsual),
          updatedAt: Value(toEpochMs(_now())),
        ),
      );
}
