import 'package:drift/drift.dart';

import '../../domain/models/photo.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class PhotosRepository {
  /// Photos of one place / product / price / menu, oldest first.
  Stream<List<Photo>> watchFor(PhotoOwner ownerType, String ownerId);

  /// Insert or update a photo record. The file itself lives in the app documents directory.
  Future<void> save(Photo photo);

  /// Soft delete the record. Removing the file is the caller's job.
  Future<void> delete(String id);
}

class DriftPhotosRepository implements PhotosRepository {
  DriftPhotosRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  @override
  Stream<List<Photo>> watchFor(PhotoOwner ownerType, String ownerId) {
    final query = _db.select(_db.photos)
      ..where(
        (p) =>
            p.ownerType.equalsValue(ownerType) &
            p.ownerId.equals(ownerId) &
            p.deletedAt.isNull(),
      )
      ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          Photo(
            id: r.id,
            ownerType: r.ownerType,
            ownerId: r.ownerId,
            filePath: r.filePath,
            ocrText: r.ocrText,
          ),
      ],
    );
  }

  @override
  Future<void> save(Photo photo) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.photos,
    )..where((p) => p.id.equals(photo.id))).getSingleOrNull();
    final values = PhotosCompanion(
      ownerType: Value(photo.ownerType),
      ownerId: Value(photo.ownerId),
      filePath: Value(photo.filePath),
      ocrText: Value(photo.ocrText),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.photos)
          .insert(values.copyWith(id: Value(photo.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.photos,
      )..where((p) => p.id.equals(photo.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return (_db.update(_db.photos)..where((p) => p.id.equals(id))).write(
      PhotosCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
