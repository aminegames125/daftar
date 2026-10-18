import 'package:drift/drift.dart';

import '../../domain/models/lookups.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class PaymentMethodsRepository {
  Stream<List<PaymentMethod>> watchAll();
  Future<void> save(PaymentMethod method);

  /// Soft delete ("hide").
  Future<void> delete(String id);
}

class DriftPaymentMethodsRepository implements PaymentMethodsRepository {
  DriftPaymentMethodsRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  @override
  Stream<List<PaymentMethod>> watchAll() {
    final query = _db.select(_db.paymentMethods)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          PaymentMethod(
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
  Future<void> save(PaymentMethod method) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.paymentMethods,
    )..where((t) => t.id.equals(method.id))).getSingleOrNull();
    final values = PaymentMethodsCompanion(
      name: Value(method.name),
      iconKey: Value(method.iconKey),
      sortOrder: Value(method.sortOrder),
      isBuiltIn: Value(method.isBuiltIn),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.paymentMethods)
          .insert(values.copyWith(id: Value(method.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.paymentMethods,
      )..where((t) => t.id.equals(method.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return (_db.update(
      _db.paymentMethods,
    )..where((t) => t.id.equals(id))).write(
      PaymentMethodsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
