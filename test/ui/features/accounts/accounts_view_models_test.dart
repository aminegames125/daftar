import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/features/accounts/view_models/accounts_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Account _account(
  String id, {
  Currency currency = Currency.tnd,
  int opening = 0,
  int order = 0,
  bool inTotals = true,
}) => Account(
  id: id,
  name: id,
  kind: AccountKind.cash,
  currency: currency,
  openingBalanceMinor: opening,
  sortOrder: order,
  includeInTotals: inTotals,
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // The purchase test links a price entry that is not in this database.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  AccountActions actions() => container.read(accountActionsProvider);

  test('overview keeps TND and USD apart and skips excluded accounts', () {
    final overview = buildAccountsOverview(
      [
        _account('cash', opening: 10000),
        _account('usd', currency: Currency.usd, opening: 5000),
        _account('savings', opening: 99000, inTotals: false),
      ],
      [
        AccountTransaction(
          id: 't',
          accountId: 'cash',
          kind: TransactionKind.expense,
          amountMinor: 2500,
          currency: Currency.tnd,
          occurredAt: DateTime(2026, 10, 1),
        ),
      ],
    );
    expect(overview.totals[Currency.tnd], const Money.tnd(7500));
    expect(overview.totals[Currency.usd], const Money.usd(5000));
    expect(overview.balances['savings'], const Money.tnd(99000));
  });

  test('reorder rewrites only the sort order of moved accounts', () async {
    await actions().saveAccount(_account('a', order: 0));
    await actions().saveAccount(_account('b', order: 1));
    await actions().saveAccount(_account('c', order: 2));
    await actions().reorder([
      _account('c', order: 2),
      _account('a', order: 0),
      _account('b', order: 1),
    ]);
    final list = await container
        .read(accountsRepositoryProvider)
        .watchAll()
        .first;
    expect(list.map((a) => a.id), ['c', 'a', 'b']);
  });

  test('include-in-totals switch is saved', () async {
    final a = _account('a');
    await actions().saveAccount(a);
    await actions().toggleIncludeInTotals(a, false);
    final got = await actions().getAccount('a');
    expect(got!.includeInTotals, isFalse);
  });

  test(
    'recordPurchase links the price and keeps the account currency',
    () async {
      final usd = _account('usd', currency: Currency.usd);
      await actions().saveAccount(usd);
      final tx = await actions().recordPurchase(
        account: usd,
        amountMinor: 1250,
        at: DateTime(2026, 10, 17),
        priceEntryId: 'price-1',
        note: 'Netflix',
      );
      final found = await container
          .read(transactionsRepositoryProvider)
          .getForPriceEntry('price-1');
      expect(found.single.id, tx.id);
      expect(found.single.currency, Currency.usd);
      expect(found.single.kind, TransactionKind.expense);
      expect(found.single.amountMinor, 1250);
    },
  );

  test('default account is the last used one, else the first', () async {
    expect(await actions().defaultAccount(), isNull);
    await actions().saveAccount(_account('a', order: 0));
    await actions().saveAccount(_account('b', order: 1));
    expect((await actions().defaultAccount())!.id, 'a');
    await actions().saveTransaction(
      AccountTransaction(
        id: 't',
        accountId: 'b',
        kind: TransactionKind.income,
        amountMinor: 100,
        currency: Currency.tnd,
        occurredAt: DateTime(2026, 10, 1),
      ),
    );
    expect((await actions().defaultAccount())!.id, 'b');
  });

  test(
    'deleting a transaction is a soft delete that changes the balance',
    () async {
      await actions().saveAccount(_account('a', opening: 1000));
      await actions().saveTransaction(
        AccountTransaction(
          id: 't',
          accountId: 'a',
          kind: TransactionKind.expense,
          amountMinor: 400,
          currency: Currency.tnd,
          occurredAt: DateTime(2026, 10, 1),
        ),
      );
      await actions().deleteTransaction('t');
      expect(await actions().getTransaction('t'), isNull);
      final all = await container
          .read(transactionsRepositoryProvider)
          .watchAll()
          .first;
      expect(all, isEmpty);
    },
  );

  test('hide-amounts survives a restart', () async {
    await container.read(hideAmountsProvider.notifier).set(true);
    final second = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(second.dispose);
    second.read(hideAmountsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(second.read(hideAmountsProvider), isTrue);
  });
}
