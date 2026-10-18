import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../domain/models/place.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class PlacesRepository {
  /// All places, A→Z.
  Stream<List<Place>> watchAll();
  Stream<Place?> watch(String id);
  Future<Place?> get(String id);

  /// Insert or update the place with its payment methods and tags.
  Future<void> save(Place place);

  /// Soft delete. Its prices and menu stay in the database.
  Future<void> delete(String id);
}

class DriftPlacesRepository implements PlacesRepository {
  DriftPlacesRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  @override
  Stream<List<Place>> watchAll() {
    final query = _db.select(_db.places)
      ..where((p) => p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.asc(p.searchKey)]);
    return query.watch().asyncMap(_withRelations);
  }

  @override
  Stream<Place?> watch(String id) {
    final query = _db.select(_db.places)
      ..where((p) => p.id.equals(id) & p.deletedAt.isNull());
    return query.watch().asyncMap(
      (rows) async => (await _withRelations(rows)).firstOrNull,
    );
  }

  @override
  Future<Place?> get(String id) async {
    final rows = await (_db.select(
      _db.places,
    )..where((p) => p.id.equals(id) & p.deletedAt.isNull())).get();
    return (await _withRelations(rows)).firstOrNull;
  }

  Future<List<Place>> _withRelations(List<PlaceRow> rows) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r.id).toList();
    final payments = await (_db.select(
      _db.placePaymentMethods,
    )..where((l) => l.placeId.isIn(ids))).get();
    final tags = await (_db.select(
      _db.placeTags,
    )..where((t) => t.placeId.isIn(ids))).get();
    final paymentsByPlace = payments.groupListsBy((l) => l.placeId);
    final tagsByPlace = tags.groupListsBy((t) => t.placeId);
    return [
      for (final r in rows)
        Place(
          id: r.id,
          name: r.name,
          typeId: r.typeId,
          lat: r.lat,
          lng: r.lng,
          address: r.address,
          phone: r.phone,
          openingHours: r.openingHours == null
              ? null
              : OpeningHours.fromJson(
                  jsonDecode(r.openingHours!) as Map<String, dynamic>,
                ),
          wifiName: r.wifiName,
          wifiPassword: r.wifiPassword,
          rating: r.rating,
          notes: r.notes,
          paymentMethodIds: [
            for (final l
                in paymentsByPlace[r.id] ?? const <PlacePaymentMethod>[])
              l.paymentMethodId,
          ],
          tags: [
            for (final t in tagsByPlace[r.id] ?? const <PlaceTag>[]) t.tag,
          ],
        ),
    ];
  }

  @override
  Future<void> save(Place place) => _db.transaction(() async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.places,
    )..where((p) => p.id.equals(place.id))).getSingleOrNull();
    final values = PlacesCompanion(
      name: Value(place.name),
      typeId: Value(place.typeId),
      lat: Value(place.lat),
      lng: Value(place.lng),
      address: Value(place.address),
      phone: Value(place.phone),
      openingHours: Value(
        place.openingHours == null
            ? null
            : jsonEncode(place.openingHours!.toJson()),
      ),
      wifiName: Value(place.wifiName),
      wifiPassword: Value(place.wifiPassword),
      rating: Value(place.rating),
      notes: Value(place.notes),
      searchKey: Value(searchKeyOf([place.name, place.address])),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.places)
          .insert(values.copyWith(id: Value(place.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.places,
      )..where((p) => p.id.equals(place.id))).write(values);
    }

    await (_db.delete(
      _db.placePaymentMethods,
    )..where((l) => l.placeId.equals(place.id))).go();
    await (_db.delete(
      _db.placeTags,
    )..where((t) => t.placeId.equals(place.id))).go();
    await _db.batch((b) {
      b.insertAll(_db.placePaymentMethods, [
        for (final id in place.paymentMethodIds.toSet())
          PlacePaymentMethodsCompanion.insert(
            placeId: place.id,
            paymentMethodId: id,
          ),
      ]);
      b.insertAll(_db.placeTags, [
        for (final tag in place.tags.toSet())
          PlaceTagsCompanion.insert(placeId: place.id, tag: tag),
      ]);
    });
  });

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return (_db.update(_db.places)..where((p) => p.id.equals(id))).write(
      PlacesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
