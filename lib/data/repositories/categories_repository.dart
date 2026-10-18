import 'package:drift/drift.dart';

import '../../domain/models/lookups.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class CategoriesRepository {
  Stream<List<Category>> watchAll();
  Future<void> save(Category category);

  /// Soft delete ("hide"). Products keep their category id.
  Future<void> delete(String id);
}

class DriftCategoriesRepository implements CategoriesRepository {
  DriftCategoriesRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  @override
  Stream<List<Category>> watchAll() {
    final query = _db.select(_db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          Category(
            id: r.id,
            name: r.name,
            iconKey: r.iconKey,
            sortOrder: r.sortOrder,
            isBuiltIn: r.isBuiltIn,
          ),
      ],
    );
  }

  @override
  Future<void> save(Category category) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.categories,
    )..where((t) => t.id.equals(category.id))).getSingleOrNull();
    final values = CategoriesCompanion(
      name: Value(category.name),
      iconKey: Value(category.iconKey),
      sortOrder: Value(category.sortOrder),
      isBuiltIn: Value(category.isBuiltIn),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.categories)
          .insert(
            values.copyWith(id: Value(category.id), createdAt: Value(now)),
          );
    } else {
      await (_db.update(
        _db.categories,
      )..where((t) => t.id.equals(category.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
