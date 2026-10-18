import 'package:drift/drift.dart';

import '../../domain/models/account.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class TransactionsRepository {
  /// Transactions of one account, newest first. [from] inclusive, [to] exclusive.
  Stream<List<AccountTransaction>> watchForAccount(
    String accountId, {
    DateTime? from,
    DateTime? to,
  });

  /// Transactions of all non-deleted accounts, newest first. [from] inclusive, [to] exclusive.
  Stream<List<AccountTransaction>> watchAll({DateTime? from, DateTime? to});

  Future<AccountTransaction?> getById(String id);

  /// Every live leg sharing [pairId] (transfers and exchanges have two).
  Future<List<AccountTransaction>> getByPairId(String pairId);

  /// The expenses linked to a logged price ("I bought it").
  Future<List<AccountTransaction>> getForPriceEntry(String priceEntryId);

  Future<void> save(AccountTransaction transaction);

  /// Saves several rows atomically (both legs of a transfer or exchange).
  Future<void> saveAll(List<AccountTransaction> transactions);

  /// Soft delete. A transfer/exchange leg takes its partner leg with it.
  Future<void> delete(String id);
}

class DriftTransactionsRepository implements TransactionsRepository {
  DriftTransactionsRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  static AccountTransaction _map(TransactionRow r) => AccountTransaction(
    id: r.id,
    accountId: r.accountId,
    kind: r.kind,
    amountMinor: r.amountMinor,
    currency: r.currency,
    occurredAt: fromEpochMs(r.occurredAt),
    categoryId: r.categoryId,
    note: r.note,
    priceEntryId: r.priceEntryId,
    pairId: r.pairId,
    feeMinor: r.feeMinor,
    rateTenThousandths: r.rateTenThousandths,
  );

  Stream<List<AccountTransaction>> _watch({
    String? accountId,
    DateTime? from,
    DateTime? to,
  }) {
    final q =
        _db.select(_db.transactions).join([
          innerJoin(
            _db.accounts,
            _db.accounts.id.equalsExp(_db.transactions.accountId),
          ),
        ])..where(
          _db.transactions.deletedAt.isNull() & _db.accounts.deletedAt.isNull(),
        );
    if (accountId != null) {
      q.where(_db.transactions.accountId.equals(accountId));
    }
    if (from != null) {
      q.where(
        _db.transactions.occurredAt.isBiggerOrEqualValue(toEpochMs(from)),
      );
    }
    if (to != null) {
      q.where(_db.transactions.occurredAt.isSmallerThanValue(toEpochMs(to)));
    }
    q.orderBy([
      OrderingTerm.desc(_db.transactions.occurredAt),
      OrderingTerm.desc(_db.transactions.createdAt),
    ]);
    return q.watch().map(
      (rows) => [for (final r in rows) _map(r.readTable(_db.transactions))],
    );
  }

  @override
  Stream<List<AccountTransaction>> watchForAccount(
    String accountId, {
    DateTime? from,
    DateTime? to,
  }) => _watch(accountId: accountId, from: from, to: to);

  @override
  Stream<List<AccountTransaction>> watchAll({DateTime? from, DateTime? to}) =>
      _watch(from: from, to: to);

  @override
  Future<AccountTransaction?> getById(String id) async {
    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<List<AccountTransaction>> getByPairId(String pairId) async {
    final rows =
        await (_db.select(_db.transactions)
              ..where((t) => t.pairId.equals(pairId) & t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return rows.map(_map).toList();
  }

  @override
  Future<List<AccountTransaction>> getForPriceEntry(String priceEntryId) async {
    final rows =
        await (_db.select(_db.transactions)
              ..where(
                (t) =>
                    t.priceEntryId.equals(priceEntryId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
            .get();
    return rows.map(_map).toList();
  }

  Future<void> _upsert(AccountTransaction x, int now) async {
    final existing = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(x.id))).getSingleOrNull();
    final values = TransactionsCompanion(
      accountId: Value(x.accountId),
      kind: Value(x.kind),
      amountMinor: Value(x.amountMinor),
      currency: Value(x.currency),
      categoryId: Value(x.categoryId),
      note: Value(x.note),
      occurredAt: Value(toEpochMs(x.occurredAt)),
      priceEntryId: Value(x.priceEntryId),
      pairId: Value(x.pairId),
      feeMinor: Value(x.feeMinor),
      rateTenThousandths: Value(x.rateTenThousandths),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.transactions)
          .insert(values.copyWith(id: Value(x.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.equals(x.id))).write(values);
    }
  }

  @override
  Future<void> save(AccountTransaction transaction) => saveAll([transaction]);

  @override
  Future<void> saveAll(List<AccountTransaction> transactions) {
    final now = toEpochMs(_now());
    return _db.transaction(() async {
      for (final x in transactions) {
        await _upsert(x, now);
      }
    });
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return _db.transaction(() async {
      final row = await (_db.select(
        _db.transactions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return;
      final pairId = row.pairId;
      await (_db.update(_db.transactions)..where(
            (t) => pairId == null
                ? t.id.equals(id)
                : t.id.equals(id) | t.pairId.equals(pairId),
          ))
          .write(
            TransactionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
          );
    });
  }
}
