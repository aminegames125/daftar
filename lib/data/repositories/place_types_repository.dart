import 'package:drift/drift.dart';

import '../../domain/models/lookups.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class PlaceTypesRepository {
  Stream<List<PlaceType>> watchAll();
  Future<PlaceType?> get(String id);

  /// Insert or update. Built-in types can be renamed too.
  Future<void> save(PlaceType type);

  /// Soft delete ("hide"). Places keep pointing at it, so it still resolves by id.
  Future<void> delete(String id);
}

class DriftPlaceTypesRepository implements PlaceTypesRepository {
  DriftPlaceTypesRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  PlaceType _map(PlaceTypeRow r) => PlaceType(
    id: r.id,
    name: r.name,
    iconKey: r.iconKey,
    kind: r.kind,
    sortOrder: r.sortOrder,
    isBuiltIn: r.isBuiltIn,
  );

  @override
  Stream<List<PlaceType>> watchAll() {
    final query = _db.select(_db.placeTypes)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    return query.watch().map((rows) => rows.map(_map).toList());
  }

  @override
  Future<PlaceType?> get(String id) async {
    final row = await (_db.select(
      _db.placeTypes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<void> save(PlaceType type) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.placeTypes,
    )..where((t) => t.id.equals(type.id))).getSingleOrNull();
    final values = PlaceTypesCompanion(
      name: Value(type.name),
      iconKey: Value(type.iconKey),
      kind: Value(type.kind),
      sortOrder: Value(type.sortOrder),
      isBuiltIn: Value(type.isBuiltIn),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.placeTypes)
          .insert(values.copyWith(id: Value(type.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.placeTypes,
      )..where((t) => t.id.equals(type.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) =>
      (_db.update(_db.placeTypes)..where((t) => t.id.equals(id))).write(
        PlaceTypesCompanion(
          deletedAt: Value(toEpochMs(_now())),
          updatedAt: Value(toEpochMs(_now())),
        ),
      );
}
