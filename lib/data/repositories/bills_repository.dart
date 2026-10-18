import 'package:drift/drift.dart';

import '../../domain/models/bill.dart';
import '../../domain/models/ids.dart';
import '../../domain/use_cases/bill_schedule.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';
import 'search_support.dart';

abstract interface class BillsRepository {
  /// Live bills ordered by next due date (soonest first), then name.
  /// Includes inactive bills; filter on [Bill.isActive] in the view model.
  Stream<List<Bill>> watchAll();
  Future<Bill?> getById(String id);
  Future<List<Bill>> search(String query);

  /// Insert or update (also restores a soft-deleted bill).
  Future<void> save(Bill bill);

  /// Soft delete the bill and its payment history.
  Future<void> delete(String id);

  /// Payments of one bill, newest first.
  Stream<List<BillPayment>> watchPayments(String billId);

  /// Payments of all live bills, newest first. [from] inclusive, [to] exclusive.
  Stream<List<BillPayment>> watchAllPayments({DateTime? from, DateTime? to});

  /// Records a payment (default amount = the bill amount, default time = now) and moves
  /// [Bill.nextDueAt] forward by one cycle, in one transaction. Returns the payment.
  Future<BillPayment> recordPayment(
    String billId, {
    int? amountMinor,
    DateTime? paidAt,
  });

  /// Soft-deletes a payment. The bill's next due date is not rolled back.
  Future<void> deletePayment(String paymentId);
}

class DriftBillsRepository implements BillsRepository {
  DriftBillsRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  static Bill _map(BillRow r) => Bill(
    id: r.id,
    name: r.name,
    amountMinor: r.amountMinor,
    currency: r.currency,
    cycle: r.cycle,
    customDays: r.customDays,
    nextDueAt: fromEpochMs(r.nextDueAt),
    reminderDaysBefore: r.reminderDaysBefore,
    isActive: r.isActive,
    iconKey: r.iconKey,
    categoryId: r.categoryId,
  );

  static BillPayment _mapPayment(BillPaymentRow r) => BillPayment(
    id: r.id,
    billId: r.billId,
    amountMinor: r.amountMinor,
    paidAt: fromEpochMs(r.paidAt),
  );

  SimpleSelectStatement<$BillsTable, BillRow> _live() => _db.select(_db.bills)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([
      (t) => OrderingTerm.asc(t.nextDueAt),
      (t) => OrderingTerm.asc(t.name),
    ]);

  @override
  Stream<List<Bill>> watchAll() =>
      _live().watch().map((rows) => rows.map(_map).toList());

  @override
  Future<Bill?> getById(String id) async {
    final row = await (_db.select(
      _db.bills,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<List<Bill>> search(String query) async {
    final q = _live();
    for (final token in searchTokens(query)) {
      q.where((t) => t.searchKey.like(likeContains(token), escapeChar: r'\'));
    }
    return (await q.get()).map(_map).toList();
  }

  @override
  Future<void> save(Bill b) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.bills,
    )..where((t) => t.id.equals(b.id))).getSingleOrNull();
    final values = BillsCompanion(
      name: Value(b.name),
      amountMinor: Value(b.amountMinor),
      currency: Value(b.currency),
      cycle: Value(b.cycle),
      customDays: Value(b.cycle == BillCycle.customDays ? b.customDays : null),
      nextDueAt: Value(toEpochMs(b.nextDueAt)),
      reminderDaysBefore: Value(b.reminderDaysBefore),
      isActive: Value(b.isActive),
      iconKey: Value(b.iconKey),
      categoryId: Value(b.categoryId),
      searchKey: Value(searchKeyOf([b.name])),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.bills)
          .insert(values.copyWith(id: Value(b.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.bills,
      )..where((t) => t.id.equals(b.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return _db.transaction(() async {
      await (_db.update(
        _db.billPayments,
      )..where((t) => t.billId.equals(id) & t.deletedAt.isNull())).write(
        BillPaymentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (_db.update(_db.bills)..where((t) => t.id.equals(id))).write(
        BillsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  @override
  Stream<List<BillPayment>> watchPayments(String billId) {
    final q = _db.select(_db.billPayments)
      ..where((t) => t.billId.equals(billId) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.paidAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    return q.watch().map((rows) => rows.map(_mapPayment).toList());
  }

  @override
  Stream<List<BillPayment>> watchAllPayments({DateTime? from, DateTime? to}) {
    final q =
        _db.select(_db.billPayments).join([
          innerJoin(_db.bills, _db.bills.id.equalsExp(_db.billPayments.billId)),
        ])..where(
          _db.billPayments.deletedAt.isNull() & _db.bills.deletedAt.isNull(),
        );
    if (from != null) {
      q.where(_db.billPayments.paidAt.isBiggerOrEqualValue(toEpochMs(from)));
    }
    if (to != null) {
      q.where(_db.billPayments.paidAt.isSmallerThanValue(toEpochMs(to)));
    }
    q.orderBy([
      OrderingTerm.desc(_db.billPayments.paidAt),
      OrderingTerm.desc(_db.billPayments.createdAt),
    ]);
    return q.watch().map(
      (rows) => [
        for (final r in rows) _mapPayment(r.readTable(_db.billPayments)),
      ],
    );
  }

  @override
  Future<BillPayment> recordPayment(
    String billId, {
    int? amountMinor,
    DateTime? paidAt,
  }) {
    final nowTime = _now();
    final now = toEpochMs(nowTime);
    return _db.transaction(() async {
      final bill = await getById(billId);
      if (bill == null) throw StateError('Bill $billId not found');
      final payment = BillPayment(
        id: newId(),
        billId: billId,
        amountMinor: amountMinor ?? bill.amountMinor,
        paidAt: paidAt ?? nowTime,
      );
      await _db
          .into(_db.billPayments)
          .insert(
            BillPaymentsCompanion.insert(
              id: payment.id,
              billId: billId,
              amountMinor: payment.amountMinor,
              paidAt: toEpochMs(payment.paidAt),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final next = nextDueDate(
        bill.nextDueAt,
        bill.cycle,
        customDays: bill.customDays,
      );
      await (_db.update(_db.bills)..where((t) => t.id.equals(billId))).write(
        BillsCompanion(
          nextDueAt: Value(toEpochMs(next)),
          updatedAt: Value(now),
        ),
      );
      return payment;
    });
  }

  @override
  Future<void> deletePayment(String paymentId) {
    final now = toEpochMs(_now());
    return (_db.update(
      _db.billPayments,
    )..where((t) => t.id.equals(paymentId))).write(
      BillPaymentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
