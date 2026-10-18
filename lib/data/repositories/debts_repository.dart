import 'package:drift/drift.dart';

import '../../domain/models/debt.dart';
import '../../domain/models/ids.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';
import 'search_support.dart';

abstract interface class DebtsRepository {
  /// Live debts, newest first. Settled debts are included; use `debtRemaining`
  /// with [watchAllPayments] to tell them apart.
  Stream<List<Debt>> watchAll();
  Future<Debt?> getById(String id);
  Future<List<Debt>> search(String query);

  /// Insert or update (also restores a soft-deleted debt).
  Future<void> save(Debt debt);

  /// Soft delete the debt and its payments.
  Future<void> delete(String id);

  /// Payments of one debt, newest first.
  Stream<List<DebtPayment>> watchPayments(String debtId);

  /// Payments of all live debts, newest first.
  Stream<List<DebtPayment>> watchAllPayments();

  /// Adds a repayment (default time = now) and returns it.
  Future<DebtPayment> addPayment(
    String debtId,
    int amountMinor, {
    DateTime? paidAt,
  });
  Future<void> deletePayment(String paymentId);
}

class DriftDebtsRepository implements DebtsRepository {
  DriftDebtsRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  static Debt _map(DebtRow r) => Debt(
    id: r.id,
    name: r.name,
    direction: r.direction,
    amountMinor: r.amountMinor,
    currency: r.currency,
    note: r.note,
    dueAt: r.dueAt == null ? null : fromEpochMs(r.dueAt!),
    sourceAccountId: r.sourceAccountId,
  );

  static DebtPayment _mapPayment(DebtPaymentRow r) => DebtPayment(
    id: r.id,
    debtId: r.debtId,
    amountMinor: r.amountMinor,
    paidAt: fromEpochMs(r.paidAt),
  );

  SimpleSelectStatement<$DebtsTable, DebtRow> _live() => _db.select(_db.debts)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.asc(t.name),
    ]);

  @override
  Stream<List<Debt>> watchAll() =>
      _live().watch().map((rows) => rows.map(_map).toList());

  @override
  Future<Debt?> getById(String id) async {
    final row = await (_db.select(
      _db.debts,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<List<Debt>> search(String query) async {
    final q = _live();
    for (final token in searchTokens(query)) {
      q.where((t) => t.searchKey.like(likeContains(token), escapeChar: r'\'));
    }
    return (await q.get()).map(_map).toList();
  }

  @override
  Future<void> save(Debt d) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.debts,
    )..where((t) => t.id.equals(d.id))).getSingleOrNull();
    final values = DebtsCompanion(
      name: Value(d.name),
      direction: Value(d.direction),
      amountMinor: Value(d.amountMinor),
      currency: Value(d.currency),
      note: Value(d.note),
      dueAt: Value(d.dueAt == null ? null : toEpochMs(d.dueAt!)),
      sourceAccountId: Value(d.sourceAccountId),
      searchKey: Value(searchKeyOf([d.name, d.note])),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.debts)
          .insert(values.copyWith(id: Value(d.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.debts,
      )..where((t) => t.id.equals(d.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return _db.transaction(() async {
      await (_db.update(
        _db.debtPayments,
      )..where((t) => t.debtId.equals(id) & t.deletedAt.isNull())).write(
        DebtPaymentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (_db.update(_db.debts)..where((t) => t.id.equals(id))).write(
        DebtsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  @override
  Stream<List<DebtPayment>> watchPayments(String debtId) {
    final q = _db.select(_db.debtPayments)
      ..where((t) => t.debtId.equals(debtId) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.paidAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    return q.watch().map((rows) => rows.map(_mapPayment).toList());
  }

  @override
  Stream<List<DebtPayment>> watchAllPayments() {
    final q =
        _db.select(_db.debtPayments).join([
            innerJoin(
              _db.debts,
              _db.debts.id.equalsExp(_db.debtPayments.debtId),
            ),
          ])
          ..where(
            _db.debtPayments.deletedAt.isNull() & _db.debts.deletedAt.isNull(),
          )
          ..orderBy([
            OrderingTerm.desc(_db.debtPayments.paidAt),
            OrderingTerm.desc(_db.debtPayments.createdAt),
          ]);
    return q.watch().map(
      (rows) => [
        for (final r in rows) _mapPayment(r.readTable(_db.debtPayments)),
      ],
    );
  }

  @override
  Future<DebtPayment> addPayment(
    String debtId,
    int amountMinor, {
    DateTime? paidAt,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError.value(amountMinor, 'amountMinor', 'must be > 0');
    }
    final nowTime = _now();
    final now = toEpochMs(nowTime);
    if (await getById(debtId) == null) {
      throw StateError('Debt $debtId not found');
    }
    final payment = DebtPayment(
      id: newId(),
      debtId: debtId,
      amountMinor: amountMinor,
      paidAt: paidAt ?? nowTime,
    );
    await _db
        .into(_db.debtPayments)
        .insert(
          DebtPaymentsCompanion.insert(
            id: payment.id,
            debtId: debtId,
            amountMinor: amountMinor,
            paidAt: toEpochMs(payment.paidAt),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return payment;
  }

  @override
  Future<void> deletePayment(String paymentId) {
    final now = toEpochMs(_now());
    return (_db.update(
      _db.debtPayments,
    )..where((t) => t.id.equals(paymentId))).write(
      DebtPaymentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
