import 'package:drift/drift.dart';

import '../../domain/models/account.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class RateEntriesRepository {
  /// Newest first. [from] inclusive, [to] exclusive.
  Stream<List<RateEntry>> watchAll({DateTime? from, DateTime? to});

  /// The most recent rate, or null when none was ever saved.
  Future<RateEntry?> latest();
  Stream<RateEntry?> watchLatest();

  /// Insert or update (also restores a soft-deleted entry).
  Future<void> save(RateEntry entry);
  Future<void> delete(String id);
}

class DriftRateEntriesRepository implements RateEntriesRepository {
  DriftRateEntriesRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  static RateEntry _map(RateEntryRow r) => RateEntry(
    id: r.id,
    date: fromEpochMs(r.date),
    tndPerUsdTenThousandths: r.tndPerUsdTenThousandths,
    sourceNote: r.sourceNote,
  );

  SimpleSelectStatement<$RateEntriesTable, RateEntryRow> _live({
    DateTime? from,
    DateTime? to,
  }) => _db.select(_db.rateEntries)
    ..where((t) {
      var cond = t.deletedAt.isNull();
      if (from != null) {
        cond = cond & t.date.isBiggerOrEqualValue(toEpochMs(from));
      }
      if (to != null) {
        cond = cond & t.date.isSmallerThanValue(toEpochMs(to));
      }
      return cond;
    })
    ..orderBy([
      (t) => OrderingTerm.desc(t.date),
      (t) => OrderingTerm.desc(t.createdAt),
    ]);

  @override
  Stream<List<RateEntry>> watchAll({DateTime? from, DateTime? to}) =>
      _live(from: from, to: to).watch().map((rows) => rows.map(_map).toList());

  @override
  Future<RateEntry?> latest() async {
    final rows = await (_live()..limit(1)).get();
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Stream<RateEntry?> watchLatest() => (_live()..limit(1)).watch().map(
    (rows) => rows.isEmpty ? null : _map(rows.first),
  );

  @override
  Future<void> save(RateEntry e) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.rateEntries,
    )..where((t) => t.id.equals(e.id))).getSingleOrNull();
    final values = RateEntriesCompanion(
      date: Value(toEpochMs(e.date)),
      tndPerUsdTenThousandths: Value(e.tndPerUsdTenThousandths),
      sourceNote: Value(e.sourceNote),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.rateEntries)
          .insert(values.copyWith(id: Value(e.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.rateEntries,
      )..where((t) => t.id.equals(e.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return (_db.update(_db.rateEntries)..where((t) => t.id.equals(id))).write(
      RateEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
