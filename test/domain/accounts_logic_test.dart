import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/bill.dart';
import 'package:daftar/domain/models/debt.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/account_balance.dart';
import 'package:daftar/domain/use_cases/bill_schedule.dart';
import 'package:daftar/domain/use_cases/debt_math.dart';
import 'package:flutter_test/flutter_test.dart';

AccountTransaction tx(
  String account,
  TransactionKind kind,
  int amount, {
  Currency currency = Currency.tnd,
  int? fee,
}) => AccountTransaction(
  id: '$account-$kind-$amount',
  accountId: account,
  kind: kind,
  amountMinor: amount,
  currency: currency,
  occurredAt: DateTime(2026, 10, 1),
  feeMinor: fee,
);

void main() {
  group('accountBalance', () {
    const cash = Account(
      id: 'c',
      name: 'Cash',
      kind: AccountKind.cash,
      currency: Currency.tnd,
      openingBalanceMinor: 100000,
    );

    test('opening balance alone', () {
      expect(accountBalance(cash, const []), const Money.tnd(100000));
    });

    test('adds income and subtracts expenses, transfers and fees', () {
      final txs = [
        tx('c', TransactionKind.income, 50000),
        tx('c', TransactionKind.expense, 12500, fee: 500),
        tx('c', TransactionKind.transferOut, 20000),
        tx('c', TransactionKind.transferIn, 1000),
      ];
      expect(
        accountBalance(cash, txs).minor,
        100000 + 50000 - 13000 - 20000 + 1000,
      );
    });

    test('exchange amounts are signed', () {
      expect(
        accountBalance(cash, [
          tx('c', TransactionKind.exchange, -30000),
          tx('c', TransactionKind.exchange, 5000),
        ]).minor,
        75000,
      );
    });

    test('ignores other accounts and can go negative', () {
      final txs = [
        tx('other', TransactionKind.income, 999),
        tx('c', TransactionKind.expense, 250000),
      ];
      expect(accountBalance(cash, txs).minor, -150000);
    });

    test('magnitude kinds reject negative amounts', () {
      expect(
        () => tx('c', TransactionKind.expense, -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('totalsByCurrency', () {
    test('sums per currency and honours include-in-totals', () {
      const a = Account(
        id: 'a',
        name: 'A',
        kind: AccountKind.cash,
        currency: Currency.tnd,
        openingBalanceMinor: 1000,
      );
      const b = Account(
        id: 'b',
        name: 'B',
        kind: AccountKind.bank,
        currency: Currency.tnd,
        openingBalanceMinor: 2000,
      );
      const s = Account(
        id: 's',
        name: 'S',
        kind: AccountKind.savings,
        currency: Currency.tnd,
        openingBalanceMinor: 9000,
        includeInTotals: false,
      );
      const usd = Account(
        id: 'u',
        name: 'U',
        kind: AccountKind.card,
        currency: Currency.usd,
        openingBalanceMinor: 500,
      );
      final txs = [
        tx('b', TransactionKind.expense, 500),
        tx('u', TransactionKind.income, 250, currency: Currency.usd),
      ];
      final totals = totalsByCurrency([a, b, s, usd], txs);
      expect(totals[Currency.tnd], const Money.tnd(2500));
      expect(totals[Currency.usd], const Money.usd(750));
      expect(
        totalsByCurrency(
          [a, b, s, usd],
          txs,
          onlyIncluded: false,
        )[Currency.tnd],
        const Money.tnd(11500),
      );
    });
  });

  group('nextDueDate', () {
    test('weekly and custom days', () {
      expect(
        nextDueDate(DateTime(2026, 10, 28, 9), BillCycle.weekly),
        DateTime(2026, 11, 4, 9),
      );
      expect(
        nextDueDate(
          DateTime(2026, 12, 25),
          BillCycle.customDays,
          customDays: 10,
        ),
        DateTime(2027, 1, 4),
      );
    });

    test('monthly keeps the day and clamps short months', () {
      expect(
        nextDueDate(DateTime(2026, 10, 15), BillCycle.monthly),
        DateTime(2026, 11, 15),
      );
      expect(
        nextDueDate(DateTime(2026, 1, 31), BillCycle.monthly),
        DateTime(2026, 2, 28),
      );
      expect(
        nextDueDate(DateTime(2028, 1, 31), BillCycle.monthly),
        DateTime(2028, 2, 29),
      );
      expect(
        nextDueDate(DateTime(2026, 12, 5), BillCycle.monthly),
        DateTime(2027, 1, 5),
      );
    });

    test('anchor day returns to the 31st after a clamped month', () {
      expect(
        nextDueDate(DateTime(2026, 2, 28), BillCycle.monthly, anchorDay: 31),
        DateTime(2026, 3, 31),
      );
    });

    test('yearly, including 29 Feb', () {
      expect(
        nextDueDate(DateTime(2026, 10, 15), BillCycle.yearly),
        DateTime(2027, 10, 15),
      );
      expect(
        nextDueDate(DateTime(2028, 2, 29), BillCycle.yearly),
        DateTime(2029, 2, 28),
      );
    });
  });

  group('nextDueAfter / daysUntilDue / isReminderDue', () {
    test('skips over several missed cycles', () {
      expect(
        nextDueAfter(
          DateTime(2026, 1, 31),
          DateTime(2026, 4, 10),
          BillCycle.monthly,
        ),
        DateTime(2026, 4, 30),
      );
    });

    test('daysUntilDue is calendar based and negative when overdue', () {
      expect(
        daysUntilDue(DateTime(2026, 10, 20, 8), DateTime(2026, 10, 17, 23)),
        3,
      );
      expect(daysUntilDue(DateTime(2026, 10, 15), DateTime(2026, 10, 17)), -2);
      expect(
        daysUntilDue(DateTime(2026, 10, 17, 23), DateTime(2026, 10, 17, 1)),
        0,
      );
    });

    test('reminder opens N days before and stays open when overdue; inactive never', () {
      final bill = Bill(
        id: 'b',
        name: 'STEG',
        amountMinor: 1000,
        currency: Currency.tnd,
        cycle: BillCycle.monthly,
        nextDueAt: DateTime(2026, 10, 20),
        reminderDaysBefore: 3,
      );
      expect(isReminderDue(bill, DateTime(2026, 10, 16)), isFalse);
      expect(isReminderDue(bill, DateTime(2026, 10, 17)), isTrue);
      expect(isReminderDue(bill, DateTime(2026, 10, 25)), isTrue);
      expect(
        isReminderDue(bill.copyWith(isActive: false), DateTime(2026, 10, 25)),
        isFalse,
      );
    });
  });

  group('debtRemaining', () {
    const debt = Debt(
      id: 'd',
      name: 'Sami',
      direction: DebtDirection.owedToMe,
      amountMinor: 100000,
      currency: Currency.tnd,
    );
    DebtPayment pay(int m, {String debtId = 'd'}) => DebtPayment(
      id: '$m$debtId',
      debtId: debtId,
      amountMinor: m,
      paidAt: DateTime(2026, 10, 1),
    );

    test('amount minus payments', () {
      expect(
        debtRemaining(debt, [pay(30000), pay(20000)]),
        const Money.tnd(50000),
      );
      expect(isDebtSettled(debt, [pay(30000)]), isFalse);
    });

    test('settled at zero, never negative, ignores other debts', () {
      expect(debtRemaining(debt, [pay(100000)]).minor, 0);
      expect(isDebtSettled(debt, [pay(100000)]), isTrue);
      expect(debtRemaining(debt, [pay(150000), pay(5, debtId: 'x')]).minor, 0);
      expect(debtRemaining(debt, [pay(7, debtId: 'x')]).minor, 100000);
    });
  });
}
