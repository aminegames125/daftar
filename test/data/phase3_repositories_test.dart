import 'package:daftar/data/repositories/accounts_repository.dart';
import 'package:daftar/data/repositories/bills_repository.dart';
import 'package:daftar/data/repositories/debts_repository.dart';
import 'package:daftar/data/repositories/rate_entries_repository.dart';
import 'package:daftar/data/repositories/saved_lists_repository.dart';
import 'package:daftar/data/repositories/transactions_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/bill.dart';
import 'package:daftar/domain/models/debt.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/saved_list.dart';
import 'package:daftar/domain/use_cases/account_balance.dart';
import 'package:daftar/domain/use_cases/debt_math.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  var clock = DateTime.utc(2026, 10, 17, 12);
  DateTime now() => clock;

  setUp(() {
    clock = DateTime.utc(2026, 10, 17, 12);
    db = AppDatabase(NativeDatabase.memory(), now);
  });
  tearDown(() => db.close());

  Account account(
    String id,
    String name, {
    Currency currency = Currency.tnd,
    int opening = 0,
    int order = 0,
  }) => Account(
    id: id,
    name: name,
    kind: AccountKind.cash,
    currency: currency,
    openingBalanceMinor: opening,
    sortOrder: order,
  );

  AccountTransaction tx(
    String id,
    String accountId,
    TransactionKind kind,
    int amount, {
    DateTime? at,
    String? pairId,
    int? fee,
    int? rate,
    Currency currency = Currency.tnd,
    String? priceEntryId,
  }) => AccountTransaction(
    id: id,
    accountId: accountId,
    kind: kind,
    amountMinor: amount,
    currency: currency,
    occurredAt: at ?? DateTime.utc(2026, 10, 1),
    pairId: pairId,
    feeMinor: fee,
    rateTenThousandths: rate,
    priceEntryId: priceEntryId,
  );

  group('AccountsRepository', () {
    test('save, order, update and soft delete', () async {
      final repo = DriftAccountsRepository(db, now: now);
      await repo.save(account('b', 'Bank', order: 1));
      await repo.save(account('a', 'Cash', order: 0, opening: 5000));
      await repo.save(account('c', 'Alpha', order: 1));
      expect((await repo.watchAll().first).map((a) => a.id), ['a', 'c', 'b']);

      final loaded = (await repo.getById('a'))!;
      expect(loaded.openingBalance, const Money.tnd(5000));
      expect(loaded.includeInTotals, isTrue);
      expect(loaded.hideAmount, isFalse);

      await repo.save(
        loaded.copyWith(
          name: 'Wallet',
          hideAmount: true,
          includeInTotals: false,
        ),
      );
      final updated = (await repo.getById('a'))!;
      expect(updated.name, 'Wallet');
      expect(updated.hideAmount, isTrue);
      expect(updated.includeInTotals, isFalse);

      await repo.delete('a');
      expect(await repo.getById('a'), isNull);
      expect((await repo.watchAll().first).map((a) => a.id), ['c', 'b']);
      final raw = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('a'))).getSingle();
      expect(raw.deletedAt, isNotNull);

      await repo.save(updated); // restores
      expect(await repo.getById('a'), isNotNull);
    });

    test('stores currency and kind, timestamps follow the clock', () async {
      final repo = DriftAccountsRepository(db, now: now);
      await repo.save(
        account(
          'u',
          'Dollars',
          currency: Currency.usd,
        ).copyWith(kind: AccountKind.savings),
      );
      final got = (await repo.getById('u'))!;
      expect(got.currency, Currency.usd);
      expect(got.kind, AccountKind.savings);
      clock = DateTime.utc(2026, 11, 1);
      await repo.save(got.copyWith(name: 'USD stash'));
      final raw = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('u'))).getSingle();
      expect(
        raw.createdAt,
        DateTime.utc(2026, 10, 17, 12).millisecondsSinceEpoch,
      );
      expect(raw.updatedAt, DateTime.utc(2026, 11, 1).millisecondsSinceEpoch);
    });

    test('search is accent- and case-insensitive', () async {
      final repo = DriftAccountsRepository(db, now: now);
      await repo.save(account('1', 'Épargne Banque'));
      await repo.save(account('2', 'Cash'));
      expect((await repo.search('epargne')).map((a) => a.id), ['1']);
      expect((await repo.search('BANQ ép')).map((a) => a.id), ['1']);
      expect(await repo.search('zzz'), isEmpty);
      expect(await repo.search('100%'), isEmpty);
    });
  });

  group('TransactionsRepository', () {
    late DriftAccountsRepository accounts;
    late DriftTransactionsRepository repo;
    setUp(() async {
      accounts = DriftAccountsRepository(db, now: now);
      repo = DriftTransactionsRepository(db, now: now);
      await accounts.save(account('cash', 'Cash', opening: 100000));
      await accounts.save(account('bank', 'Bank'));
      await accounts.save(account('usd', 'USD', currency: Currency.usd));
    });

    test('newest first, range filter, per account', () async {
      await repo.save(
        tx(
          't1',
          'cash',
          TransactionKind.expense,
          1000,
          at: DateTime.utc(2026, 10, 1),
        ),
      );
      await repo.save(
        tx(
          't2',
          'cash',
          TransactionKind.income,
          5000,
          at: DateTime.utc(2026, 10, 10),
        ),
      );
      await repo.save(
        tx(
          't3',
          'bank',
          TransactionKind.income,
          7000,
          at: DateTime.utc(2026, 10, 5),
        ),
      );
      expect((await repo.watchAll().first).map((t) => t.id), [
        't2',
        't3',
        't1',
      ]);
      expect((await repo.watchForAccount('cash').first).map((t) => t.id), [
        't2',
        't1',
      ]);
      final oct5to10 = await repo
          .watchAll(
            from: DateTime.utc(2026, 10, 5),
            to: DateTime.utc(2026, 10, 10),
          )
          .first;
      expect(oct5to10.map((t) => t.id), ['t3']);
    });

    test('round-trips every field', () async {
      final price = await _insertPrice(db);
      await repo.save(
        AccountTransaction(
          id: 'x',
          accountId: 'cash',
          kind: TransactionKind.expense,
          amountMinor: 4400,
          currency: Currency.tnd,
          occurredAt: DateTime.utc(2026, 10, 3, 8),
          categoryId: builtInId('category', 'food'),
          note: 'Milk',
          priceEntryId: price,
          feeMinor: 100,
          rateTenThousandths: 31250,
        ),
      );
      final got = (await repo.getById('x'))!;
      expect(got.note, 'Milk');
      expect(got.priceEntryId, price);
      expect(got.feeMinor, 100);
      expect(got.rateTenThousandths, 31250);
      expect(got.occurredAt.toUtc(), DateTime.utc(2026, 10, 3, 8));
      expect((await repo.getForPriceEntry(price)).map((t) => t.id), ['x']);
    });

    test('transfer pair is saved atomically and deleted together', () async {
      await repo.saveAll([
        tx('o', 'cash', TransactionKind.transferOut, 20000, pairId: 'p'),
        tx('i', 'bank', TransactionKind.transferIn, 20000, pairId: 'p'),
      ]);
      expect((await repo.getByPairId('p')).length, 2);
      await repo.delete('i');
      expect(await repo.getByPairId('p'), isEmpty);
      expect(await repo.getById('o'), isNull);
    });

    test('a failing saveAll rolls everything back', () async {
      await expectLater(
        repo.saveAll([
          tx('ok', 'cash', TransactionKind.income, 1),
          tx('bad', 'missing-account', TransactionKind.income, 1),
        ]),
        throwsA(anything),
      );
      expect(await repo.getById('ok'), isNull);
    });

    test('exchange legs and balances computed from stored rows', () async {
      await repo.saveAll([
        tx(
          'e1',
          'cash',
          TransactionKind.exchange,
          -31250,
          pairId: 'x',
          rate: 31250,
          fee: 250,
        ),
        tx(
          'e2',
          'usd',
          TransactionKind.exchange,
          1000,
          pairId: 'x',
          rate: 31250,
          currency: Currency.usd,
        ),
      ]);
      await repo.save(tx('inc', 'cash', TransactionKind.income, 2000));
      final all = await repo.watchAll().first;
      final accs = await accounts.watchAll().first;
      final totals = totalsByCurrency(accs, all);
      expect(
        totals[Currency.tnd],
        const Money.tnd(100000 - 31250 - 250 + 2000),
      );
      expect(totals[Currency.usd], const Money.usd(1000));
    });

    test('deleting an account hides its transactions from watchAll', () async {
      await repo.save(tx('t1', 'bank', TransactionKind.income, 10));
      await accounts.delete('bank');
      expect(await repo.watchAll().first, isEmpty);
    });

    test('delete of an unknown id is a no-op', () async {
      await repo.delete('nope');
    });
  });

  group('RateEntriesRepository', () {
    test('latest is the newest by date, soft delete falls back', () async {
      final repo = DriftRateEntriesRepository(db, now: now);
      expect(await repo.latest(), isNull);
      await repo.save(
        RateEntry(
          id: 'r1',
          date: DateTime.utc(2026, 10, 1),
          tndPerUsdTenThousandths: 31000,
        ),
      );
      await repo.save(
        RateEntry(
          id: 'r2',
          date: DateTime.utc(2026, 10, 10),
          tndPerUsdTenThousandths: 31250,
          sourceNote: 'bank',
        ),
      );
      await repo.save(
        RateEntry(
          id: 'r0',
          date: DateTime.utc(2026, 9, 1),
          tndPerUsdTenThousandths: 30500,
        ),
      );
      final latest = (await repo.latest())!;
      expect(latest.id, 'r2');
      expect(latest.tndPerUsdTenThousandths, 31250);
      expect(latest.sourceNote, 'bank');
      expect((await repo.watchAll().first).map((r) => r.id), [
        'r2',
        'r1',
        'r0',
      ]);
      expect(
        (await repo
                .watchAll(
                  from: DateTime.utc(2026, 10, 1),
                  to: DateTime.utc(2026, 10, 10),
                )
                .first)
            .map((r) => r.id),
        ['r1'],
      );
      await repo.delete('r2');
      expect((await repo.watchLatest().first)!.id, 'r1');
    });

    test('rejects a non-positive rate', () {
      expect(
        () => RateEntry(
          id: 'x',
          date: DateTime.utc(2026),
          tndPerUsdTenThousandths: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('SavedListsRepository', () {
    test('lists: CRUD, order, search, soft delete cascades to items', () async {
      final repo = DriftSavedListsRepository(db, now: now);
      await repo.save(
        const SavedList(id: 'l2', name: 'Pharmacie', sortOrder: 1),
      );
      await repo.save(const SavedList(id: 'l1', name: 'Monthly groceries'));
      expect((await repo.watchAll().first).map((l) => l.id), ['l1', 'l2']);
      expect((await repo.search('pharm')).map((l) => l.id), ['l2']);
      await repo.saveItem(
        const SavedListItem(id: 'i1', listId: 'l1', freeText: 'Bread'),
      );
      await repo.delete('l1');
      expect(await repo.getById('l1'), isNull);
      expect(await repo.watchItems('l1').first, isEmpty);
      expect((await repo.watchAll().first).map((l) => l.id), ['l2']);
    });

    test('items: variant or free text, check, quantity, reorder, uncheck all, delete', () async {
      final repo = DriftSavedListsRepository(db, now: now);
      await repo.save(const SavedList(id: 'l', name: 'L'));
      final variantId = await _insertVariant(db);
      await repo.saveItem(
        SavedListItem(
          id: 'a',
          listId: 'l',
          variantId: variantId,
          quantity: 2,
          sortOrder: 0,
        ),
      );
      await repo.saveItem(
        const SavedListItem(
          id: 'b',
          listId: 'l',
          freeText: 'Eggs',
          sortOrder: 1,
        ),
      );
      await repo.saveItem(
        const SavedListItem(
          id: 'c',
          listId: 'l',
          freeText: 'Tea',
          sortOrder: 2,
        ),
      );

      var items = await repo.watchItems('l').first;
      expect(items.map((i) => i.id), ['a', 'b', 'c']);
      expect(items.first.variantId, variantId);
      expect(items.first.quantity, 2);
      expect(items[1].freeText, 'Eggs');

      await repo.setChecked('b', true);
      await repo.setChecked('c', true);
      await repo.setQuantity('a', 5);
      items = await repo.watchItems('l').first;
      expect(items.map((i) => i.isChecked), [false, true, true]);
      expect(items.first.quantity, 5);
      expect(() => repo.setQuantity('a', 0), throwsArgumentError);

      await repo.uncheckAll('l');
      expect(
        (await repo.watchItems('l').first).any((i) => i.isChecked),
        isFalse,
      );

      await repo.reorderItems('l', ['c', 'a', 'b']);
      expect((await repo.watchItems('l').first).map((i) => i.id), [
        'c',
        'a',
        'b',
      ]);

      await repo.deleteItem('a');
      expect((await repo.watchItems('l').first).map((i) => i.id), ['c', 'b']);
    });

    test('item needs exactly one of variant / free text', () {
      expect(
        () => SavedListItem(id: 'x', listId: 'l'),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () =>
            SavedListItem(id: 'x', listId: 'l', variantId: 'v', freeText: 't'),
        throwsA(isA<AssertionError>()),
      );
    });

    test(
      'database also enforces the variant xor free-text constraint',
      () async {
        final repo = DriftSavedListsRepository(db, now: now);
        await repo.save(const SavedList(id: 'l', name: 'L'));
        await expectLater(
          db
              .into(db.savedListItems)
              .insert(
                SavedListItemsCompanion.insert(
                  id: 'z',
                  listId: 'l',
                  createdAt: 1,
                  updatedAt: 1,
                ),
              ),
          throwsA(anything),
        );
      },
    );
  });

  group('BillsRepository', () {
    Bill bill(
      String id,
      String name,
      DateTime due, {
      BillCycle cycle = BillCycle.monthly,
      int? days,
    }) => Bill(
      id: id,
      name: name,
      amountMinor: 45000,
      currency: Currency.tnd,
      cycle: cycle,
      customDays: days,
      nextDueAt: due,
    );

    test('ordered by next due date; search; update; soft delete cascades to payments', () async {
      final repo = DriftBillsRepository(db, now: now);
      await repo.save(bill('b2', 'STEG', DateTime.utc(2026, 11, 20)));
      await repo.save(
        bill('b1', 'Ooredoo internet', DateTime.utc(2026, 11, 2)),
      );
      expect((await repo.watchAll().first).map((b) => b.id), ['b1', 'b2']);
      expect((await repo.search('steg')).map((b) => b.id), ['b2']);

      final b = (await repo.getById('b1'))!;
      expect(b.amount, const Money.tnd(45000));
      expect(b.reminderDaysBefore, 3);
      expect(b.isActive, isTrue);
      await repo.save(
        b.copyWith(isActive: false, reminderDaysBefore: 7, amountMinor: 50000),
      );
      final u = (await repo.getById('b1'))!;
      expect(
        [u.isActive, u.reminderDaysBefore, u.amountMinor],
        [false, 7, 50000],
      );

      await repo.recordPayment('b1');
      await repo.delete('b1');
      expect(await repo.getById('b1'), isNull);
      expect(await repo.watchPayments('b1').first, isEmpty);
      expect(await repo.watchAllPayments().first, isEmpty);
    });

    test('recordPayment writes history and advances the due date', () async {
      final repo = DriftBillsRepository(db, now: now);
      await repo.save(bill('m', 'STEG', DateTime(2026, 1, 31)));
      final p1 = await repo.recordPayment(
        'm',
        paidAt: DateTime.utc(2026, 1, 30),
      );
      expect(p1.amountMinor, 45000);
      expect((await repo.getById('m'))!.nextDueAt, DateTime(2026, 2, 28));

      clock = DateTime.utc(2026, 2, 27);
      await repo.recordPayment('m', amountMinor: 47000);
      expect((await repo.getById('m'))!.nextDueAt, DateTime(2026, 3, 28));

      final history = await repo.watchPayments('m').first;
      expect(history.map((p) => p.amountMinor), [47000, 45000]); // newest first
      expect(
        (await repo.watchAllPayments(from: DateTime.utc(2026, 2, 1)).first)
            .length,
        1,
      );

      await repo.deletePayment(history.first.id);
      expect((await repo.watchPayments('m').first).length, 1);
    });

    test('weekly, custom and yearly cycles', () async {
      final repo = DriftBillsRepository(db, now: now);
      await repo.save(
        bill('w', 'Weekly', DateTime(2026, 10, 17), cycle: BillCycle.weekly),
      );
      await repo.save(
        bill(
          'c',
          'Custom',
          DateTime(2026, 10, 17),
          cycle: BillCycle.customDays,
          days: 45,
        ),
      );
      await repo.save(
        bill('y', 'Netflix', DateTime(2026, 10, 17), cycle: BillCycle.yearly),
      );
      for (final id in ['w', 'c', 'y']) {
        await repo.recordPayment(id);
      }
      expect((await repo.getById('w'))!.nextDueAt, DateTime(2026, 10, 24));
      expect((await repo.getById('c'))!.nextDueAt, DateTime(2026, 12, 1));
      expect((await repo.getById('y'))!.nextDueAt, DateTime(2027, 10, 17));
    });

    test('recordPayment on a missing bill fails and writes nothing', () async {
      final repo = DriftBillsRepository(db, now: now);
      await expectLater(repo.recordPayment('nope'), throwsStateError);
      expect(await db.select(db.billPayments).get(), isEmpty);
    });

    test('custom cycle needs days', () {
      expect(
        () => Bill(
          id: 'x',
          name: 'x',
          amountMinor: 1,
          currency: Currency.tnd,
          cycle: BillCycle.customDays,
          nextDueAt: DateTime(2026),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('DebtsRepository', () {
    Debt debt(
      String id,
      String name, {
      DebtDirection d = DebtDirection.owedToMe,
      String? account,
    }) => Debt(
      id: id,
      name: name,
      direction: d,
      amountMinor: 100000,
      currency: Currency.tnd,
      note: 'for the car',
      dueAt: DateTime.utc(2026, 12, 1),
      sourceAccountId: account,
    );

    test(
      'CRUD, directions, optional source account, search by name and note',
      () async {
        final accounts = DriftAccountsRepository(db, now: now);
        final repo = DriftDebtsRepository(db, now: now);
        await accounts.save(account('sav', 'Savings'));
        await repo.save(debt('d1', 'Sami'));
        clock = DateTime.utc(2026, 10, 18);
        await repo.save(
          debt(
            'd2',
            'Savings loan',
            d: DebtDirection.iOweMyself,
            account: 'sav',
          ),
        );
        await repo.save(debt('d3', 'Landlord', d: DebtDirection.iOwe));

        expect((await repo.watchAll().first).map((d) => d.id), [
          'd3',
          'd2',
          'd1',
        ]); // newest first
        final d2 = (await repo.getById('d2'))!;
        expect(d2.direction, DebtDirection.iOweMyself);
        expect(d2.sourceAccountId, 'sav');
        expect(d2.dueAt!.toUtc(), DateTime.utc(2026, 12, 1));
        expect((await repo.getById('d1'))!.sourceAccountId, isNull);
        expect((await repo.search('sami')).map((d) => d.id), ['d1']);
        expect((await repo.search('car')).length, 3);

        await repo.save(
          const Debt(
            id: 'd1',
            name: 'Sami B',
            direction: DebtDirection.owedToMe,
            amountMinor: 1,
            currency: Currency.usd,
          ),
        );
        final d1 = (await repo.getById('d1'))!;
        expect(
          [d1.name, d1.amountMinor, d1.currency, d1.dueAt, d1.note],
          ['Sami B', 1, Currency.usd, null, null],
        );
      },
    );

    test(
      'payments reduce the remaining amount; deleting a payment restores it',
      () async {
        final repo = DriftDebtsRepository(db, now: now);
        await repo.save(debt('d', 'Sami'));
        await repo.addPayment('d', 30000, paidAt: DateTime.utc(2026, 10, 1));
        final p2 = await repo.addPayment(
          'd',
          20000,
          paidAt: DateTime.utc(2026, 10, 5),
        );
        final d = (await repo.getById('d'))!;
        var payments = await repo.watchPayments('d').first;
        expect(payments.map((p) => p.amountMinor), [20000, 30000]);
        expect(debtRemaining(d, payments), const Money.tnd(50000));

        await repo.deletePayment(p2.id);
        payments = await repo.watchAllPayments().first;
        expect(debtRemaining(d, payments), const Money.tnd(70000));
      },
    );

    test(
      'rejects bad payments; deleting a debt removes its payments',
      () async {
        final repo = DriftDebtsRepository(db, now: now);
        await repo.save(debt('d', 'Sami'));
        await expectLater(repo.addPayment('d', 0), throwsArgumentError);
        await expectLater(repo.addPayment('missing', 5), throwsStateError);
        await repo.addPayment('d', 5);
        await repo.delete('d');
        expect(await repo.getById('d'), isNull);
        expect(await repo.watchPayments('d').first, isEmpty);
        expect(await repo.watchAllPayments().first, isEmpty);
      },
    );
  });

  group('every v2 row carries the base columns', () {
    test('tables exist with id, created_at, updated_at, deleted_at', () async {
      for (final t in [
        'accounts',
        'transactions',
        'rate_entries',
        'saved_lists',
        'saved_list_items',
        'bills',
        'bill_payments',
        'debts',
        'debt_payments',
      ]) {
        final cols = await db.customSelect('PRAGMA table_info($t)').get();
        final names = cols.map((c) => c.read<String>('name')).toSet();
        expect(
          names,
          containsAll(['id', 'created_at', 'updated_at', 'deleted_at']),
          reason: t,
        );
      }
    });
  });
}

Future<String> _insertVariant(AppDatabase db) async {
  await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: 'prod',
          name: 'Milk',
          searchKey: 'milk',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
  final repoVariant = VariantsCompanion.insert(
    id: 'var',
    productId: 'prod',
    searchKey: 'milk',
    createdAt: 1,
    updatedAt: 1,
  );
  await db.into(db.variants).insert(repoVariant);
  return 'var';
}

Future<String> _insertPrice(AppDatabase db) async {
  final variantId = await _insertVariant(db);
  await db
      .into(db.places)
      .insert(
        PlacesCompanion.insert(
          id: 'pl',
          name: 'Shop',
          typeId: builtInId('place_type', 'supermarket'),
          searchKey: 'shop',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
  await db
      .into(db.priceEntries)
      .insert(
        PriceEntriesCompanion.insert(
          id: 'pe',
          variantId: Value(variantId),
          placeId: const Value('pl'),
          amountMinor: 4400,
          seenAt: 1,
          createdAt: 1,
          updatedAt: 1,
        ),
      );
  return 'pe';
}
