import 'package:drift/drift.dart';

import '../../domain/models/saved_list.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';
import 'search_support.dart';

abstract interface class SavedListsRepository {
  /// Live lists, ordered by sort order then name.
  Stream<List<SavedList>> watchAll();
  Future<SavedList?> getById(String id);
  Future<List<SavedList>> search(String query);

  /// Insert or update (also restores a soft-deleted list).
  Future<void> save(SavedList list);

  /// Soft delete the list and all its items.
  Future<void> delete(String id);

  /// Items of a list, ordered by sort order (then creation).
  Stream<List<SavedListItem>> watchItems(String listId);

  /// Insert or update an item.
  Future<void> saveItem(SavedListItem item);
  Future<void> setChecked(String itemId, bool checked);
  Future<void> setQuantity(String itemId, int quantity);
  Future<void> deleteItem(String itemId);

  /// Un-check every item of the list ("start a new shopping trip").
  Future<void> uncheckAll(String listId);

  /// Re-number sort order following [itemIds].
  Future<void> reorderItems(String listId, List<String> itemIds);
}

class DriftSavedListsRepository implements SavedListsRepository {
  DriftSavedListsRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  static SavedList _mapList(SavedListRow r) =>
      SavedList(id: r.id, name: r.name, sortOrder: r.sortOrder);

  static SavedListItem _mapItem(SavedListItemRow r) => SavedListItem(
    id: r.id,
    listId: r.listId,
    variantId: r.variantId,
    freeText: r.freeText,
    quantity: r.quantity,
    isChecked: r.isChecked,
    sortOrder: r.sortOrder,
  );

  SimpleSelectStatement<$SavedListsTable, SavedListRow> _liveLists() =>
      _db.select(_db.savedLists)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.name),
        ]);

  @override
  Stream<List<SavedList>> watchAll() =>
      _liveLists().watch().map((rows) => rows.map(_mapList).toList());

  @override
  Future<SavedList?> getById(String id) async {
    final row = await (_db.select(
      _db.savedLists,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _mapList(row);
  }

  @override
  Future<List<SavedList>> search(String query) async {
    final q = _liveLists();
    for (final token in searchTokens(query)) {
      q.where((t) => t.searchKey.like(likeContains(token), escapeChar: r'\'));
    }
    return (await q.get()).map(_mapList).toList();
  }

  @override
  Future<void> save(SavedList list) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.savedLists,
    )..where((t) => t.id.equals(list.id))).getSingleOrNull();
    final values = SavedListsCompanion(
      name: Value(list.name),
      sortOrder: Value(list.sortOrder),
      searchKey: Value(searchKeyOf([list.name])),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.savedLists)
          .insert(values.copyWith(id: Value(list.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.savedLists,
      )..where((t) => t.id.equals(list.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return _db.transaction(() async {
      await (_db.update(
        _db.savedListItems,
      )..where((t) => t.listId.equals(id) & t.deletedAt.isNull())).write(
        SavedListItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (_db.update(_db.savedLists)..where((t) => t.id.equals(id))).write(
        SavedListsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  @override
  Stream<List<SavedListItem>> watchItems(String listId) {
    final q = _db.select(_db.savedListItems)
      ..where((t) => t.listId.equals(listId) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return q.watch().map((rows) => rows.map(_mapItem).toList());
  }

  @override
  Future<void> saveItem(SavedListItem item) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.savedListItems,
    )..where((t) => t.id.equals(item.id))).getSingleOrNull();
    final values = SavedListItemsCompanion(
      listId: Value(item.listId),
      variantId: Value(item.variantId),
      freeText: Value(item.freeText),
      quantity: Value(item.quantity),
      isChecked: Value(item.isChecked),
      sortOrder: Value(item.sortOrder),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.savedListItems)
          .insert(values.copyWith(id: Value(item.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.savedListItems,
      )..where((t) => t.id.equals(item.id))).write(values);
    }
  }

  Future<void> _patchItem(String id, SavedListItemsCompanion patch) {
    final now = toEpochMs(_now());
    return (_db.update(_db.savedListItems)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .write(patch.copyWith(updatedAt: Value(now)));
  }

  @override
  Future<void> setChecked(String itemId, bool checked) =>
      _patchItem(itemId, SavedListItemsCompanion(isChecked: Value(checked)));

  @override
  Future<void> setQuantity(String itemId, int quantity) {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be > 0');
    }
    return _patchItem(
      itemId,
      SavedListItemsCompanion(quantity: Value(quantity)),
    );
  }

  @override
  Future<void> deleteItem(String itemId) {
    final now = toEpochMs(_now());
    return (_db.update(
      _db.savedListItems,
    )..where((t) => t.id.equals(itemId))).write(
      SavedListItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  @override
  Future<void> uncheckAll(String listId) {
    final now = toEpochMs(_now());
    return (_db.update(_db.savedListItems)..where(
          (t) =>
              t.listId.equals(listId) &
              t.deletedAt.isNull() &
              t.isChecked.equals(true),
        ))
        .write(
          SavedListItemsCompanion(
            isChecked: const Value(false),
            updatedAt: Value(now),
          ),
        );
  }

  @override
  Future<void> reorderItems(String listId, List<String> itemIds) {
    final now = toEpochMs(_now());
    return _db.transaction(() async {
      for (final (i, id) in itemIds.indexed) {
        await (_db.update(
          _db.savedListItems,
        )..where((t) => t.id.equals(id) & t.listId.equals(listId))).write(
          SavedListItemsCompanion(sortOrder: Value(i), updatedAt: Value(now)),
        );
      }
    });
  }
}
