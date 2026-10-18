import 'package:drift/drift.dart';

import '../../domain/models/lookups.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class GlobalPriceTypesRepository {
  Stream<List<GlobalPriceType>> watchAll();
  Future<void> save(GlobalPriceType type);

  /// Soft delete ("hide"). Existing prices keep their label.
  Future<void> delete(String id);
}

class DriftGlobalPriceTypesRepository implements GlobalPriceTypesRepository {
  DriftGlobalPriceTypesRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  @override
  Stream<List<GlobalPriceType>> watchAll() {
    final query = _db.select(_db.globalPriceTypes)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          GlobalPriceType(
            id: r.id,
            name: r.name,
            sortOrder: r.sortOrder,
            isBuiltIn: r.isBuiltIn,
          ),
      ],
    );
  }

  @override
  Future<void> save(GlobalPriceType type) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.globalPriceTypes,
    )..where((t) => t.id.equals(type.id))).getSingleOrNull();
    final values = GlobalPriceTypesCompanion(
      name: Value(type.name),
      sortOrder: Value(type.sortOrder),
      isBuiltIn: Value(type.isBuiltIn),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.globalPriceTypes)
          .insert(values.copyWith(id: Value(type.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.globalPriceTypes,
      )..where((t) => t.id.equals(type.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return (_db.update(
      _db.globalPriceTypes,
    )..where((t) => t.id.equals(id))).write(
      GlobalPriceTypesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
