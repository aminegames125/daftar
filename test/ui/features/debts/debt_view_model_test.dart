import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/debt.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/features/debts/view_models/debt_actions.dart';
import 'package:daftar/ui/features/debts/view_models/debt_items.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Debt debt(
  String id, {
  DebtDirection direction = DebtDirection.owedToMe,
  int amount = 100000,
  Currency currency = Currency.tnd,
  DateTime? due,
  String? account,
}) => Debt(
  id: id,
  name: 'Person $id',
  direction: direction,
  amountMinor: amount,
  currency: currency,
  dueAt: due,
  sourceAccountId: account,
);

void main() {
  final now = DateTime(2026, 10, 17, 12);

  group('buildDebtItems', () {
    test('remaining, progress and settled follow the payments', () {
      final d = debt('a');
      final items = buildDebtItems(
        [d],
        [
          DebtPayment(id: 'p1', debtId: 'a', amountMinor: 25000, paidAt: now),
          DebtPayment(id: 'p2', debtId: 'a', amountMinor: 25000, paidAt: now),
          DebtPayment(id: 'x', debtId: 'other', amountMinor: 99, paidAt: now),
        ],
        now,
      );
      expect(items.single.remaining.minor, 50000);
      expect(items.single.progress, 0.5);
      expect(items.single.settled, isFalse);
      expect(items.single.payments, hasLength(2));
    });

    test('fully paid is settled with progress 1', () {
      final items = buildDebtItems(
        [debt('a', amount: 1000)],
        [DebtPayment(id: 'p', debtId: 'a', amountMinor: 1000, paidAt: now)],
        now,
      );
      expect(items.single.settled, isTrue);
      expect(items.single.progress, 1);
    });

    test('overdue only when unpaid and due before today', () {
      final yesterday = DateTime(2026, 10, 16, 23);
      final today = DateTime(2026, 10, 17, 1);
      final items = buildDebtItems(
        [
          debt('late', due: yesterday),
          debt('today', due: today),
          debt('none'),
          debt('paid', due: yesterday, amount: 10),
        ],
        [DebtPayment(id: 'p', debtId: 'paid', amountMinor: 10, paidAt: now)],
        now,
      );
      expect(items.map((i) => i.overdue), [true, false, false, false]);
    });
  });

  group('totalsOf', () {
    test('keeps currencies apart and counts I owe myself as owed by me', () {
      final items = buildDebtItems(
        [
          debt('a', amount: 5000),
          debt('b', amount: 700, currency: Currency.usd),
          debt('c', direction: DebtDirection.iOwe, amount: 2000),
          debt('d', direction: DebtDirection.iOweMyself, amount: 3000),
          debt('e', amount: 9999),
        ],
        [DebtPayment(id: 'p', debtId: 'e', amountMinor: 9999, paidAt: now)],
        now,
      );
      final totals = totalsOf(items);
      expect(totals.owedToMe, {Currency.tnd: 5000, Currency.usd: 700});
      expect(totals.owedByMe, {Currency.tnd: 5000});
      expect(moneyList(totals.owedToMe), [
        const Money.tnd(5000),
        const Money.usd(700),
      ]);
      expect(const DebtTotals().isEmpty, isTrue);
    });
  });

  group('DebtActions with a real in-memory database', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<DebtItem> item(String id) async {
      final d = (await container.read(debtsRepositoryProvider).getById(id))!;
      final p = await container
          .read(debtsRepositoryProvider)
          .watchPayments(id)
          .first;
      return buildDebtItems([d], p, now).single;
    }

    test('partial then final payment settles the debt', () async {
      final actions = container.read(debtActionsProvider);
      await actions.save(debt('a', amount: 10000));
      expect(await actions.addPayment(await item('a'), 4000), isFalse);
      expect((await item('a')).remaining.minor, 6000);
      // Over-paying is clamped to what is left.
      expect(await actions.addPayment(await item('a'), 99999), isTrue);
      final done = await item('a');
      expect(done.settled, isTrue);
      expect(done.paid.minor, 10000);
    });

    test('mirror logs income / expense only when switched on', () async {
      await container
          .read(accountsRepositoryProvider)
          .save(
            const Account(
              id: 'acc',
              name: 'Savings',
              kind: AccountKind.savings,
              currency: Currency.tnd,
            ),
          );
      final actions = container.read(debtActionsProvider);
      await actions.save(debt('a', account: 'acc'));
      await actions.save(
        debt('b', direction: DebtDirection.iOwe, account: 'acc'),
      );
      await actions.save(
        debt('c', direction: DebtDirection.iOweMyself, account: 'acc'),
      );
      await actions.addPayment(await item('a'), 1000);
      expect(
        await container
            .read(transactionsRepositoryProvider)
            .watchForAccount('acc')
            .first,
        isEmpty,
      );

      await actions.addPayment(await item('a'), 1000, mirrorToAccount: true);
      await actions.addPayment(await item('b'), 2000, mirrorToAccount: true);
      await actions.addPayment(await item('c'), 3000, mirrorToAccount: true);
      final txs = await container
          .read(transactionsRepositoryProvider)
          .watchForAccount('acc')
          .first;
      final byAmount = {for (final t in txs) t.amountMinor: t.kind};
      expect(byAmount, {
        1000: TransactionKind.income,
        2000: TransactionKind.expense,
        3000: TransactionKind.income,
      });
    });

    test('no mirror when currencies differ', () async {
      await container
          .read(accountsRepositoryProvider)
          .save(
            const Account(
              id: 'usd',
              name: 'Dollars',
              kind: AccountKind.cash,
              currency: Currency.usd,
            ),
          );
      final actions = container.read(debtActionsProvider);
      final d = debt('a', account: 'usd');
      await actions.save(d);
      expect(await actions.canMirror(d), isFalse);
      await actions.addPayment(await item('a'), 1000, mirrorToAccount: true);
      expect(
        await container
            .read(transactionsRepositoryProvider)
            .watchForAccount('usd')
            .first,
        isEmpty,
      );
    });

    test('delete removes the debt', () async {
      final actions = container.read(debtActionsProvider);
      await actions.save(debt('a'));
      await actions.delete('a');
      expect(
        await container.read(debtsRepositoryProvider).getById('a'),
        isNull,
      );
    });
  });
}
