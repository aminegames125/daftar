import 'package:drift/drift.dart';

import '../../domain/models/account.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';
import 'search_support.dart';

abstract interface class AccountsRepository {
  /// Live accounts, ordered by sort order then name.
  Stream<List<Account>> watchAll();
  Future<Account?> getById(String id);

  /// Insert or update (also restores a soft-deleted account with the same id).
  Future<void> save(Account account);

  /// Soft delete. Its transactions stay in the database but are no longer listed.
  Future<void> delete(String id);

  /// Accounts whose normalised name contains every token of [query].
  Future<List<Account>> search(String query);
}

class DriftAccountsRepository implements AccountsRepository {
  DriftAccountsRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  static Account _map(AccountRow r) => Account(
    id: r.id,
    name: r.name,
    kind: r.kind,
    currency: r.currency,
    openingBalanceMinor: r.openingBalanceMinor,
    includeInTotals: r.includeInTotals,
    hideAmount: r.hideAmount,
    sortOrder: r.sortOrder,
    iconKey: r.iconKey,
  );

  SimpleSelectStatement<$AccountsTable, AccountRow> _live() =>
      _db.select(_db.accounts)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.name),
        ]);

  @override
  Stream<List<Account>> watchAll() =>
      _live().watch().map((rows) => rows.map(_map).toList());

  @override
  Future<Account?> getById(String id) async {
    final row = await (_db.select(
      _db.accounts,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<void> save(Account a) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.accounts,
    )..where((t) => t.id.equals(a.id))).getSingleOrNull();
    final values = AccountsCompanion(
      name: Value(a.name),
      kind: Value(a.kind),
      currency: Value(a.currency),
      openingBalanceMinor: Value(a.openingBalanceMinor),
      includeInTotals: Value(a.includeInTotals),
      hideAmount: Value(a.hideAmount),
      sortOrder: Value(a.sortOrder),
      iconKey: Value(a.iconKey),
      searchKey: Value(searchKeyOf([a.name])),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.accounts)
          .insert(values.copyWith(id: Value(a.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.accounts,
      )..where((t) => t.id.equals(a.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  @override
  Future<List<Account>> search(String query) async {
    final q = _live();
    for (final token in searchTokens(query)) {
      q.where((t) => t.searchKey.like(likeContains(token), escapeChar: r'\'));
    }
    return (await q.get()).map(_map).toList();
  }
}
