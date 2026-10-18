import 'package:daftar/domain/models/bill.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/bill_reminder_plan.dart';
import 'package:daftar/domain/use_cases/bill_summary.dart';
import 'package:flutter_test/flutter_test.dart';

Bill bill({
  String id = 'b',
  int amount = 10000,
  Currency currency = Currency.tnd,
  BillCycle cycle = BillCycle.monthly,
  int? customDays,
  DateTime? due,
  int remind = 3,
  bool active = true,
}) => Bill(
  id: id,
  name: id,
  amountMinor: amount,
  currency: currency,
  cycle: cycle,
  customDays: customDays,
  nextDueAt: due ?? DateTime(2026, 10, 20),
  reminderDaysBefore: remind,
  isActive: active,
);

void main() {
  final now = DateTime(2026, 10, 17, 14);

  test('status: overdue, due soon, later, paused', () {
    expect(
      billStatus(bill(due: DateTime(2026, 10, 16)), now),
      BillStatus.overdue,
    );
    expect(
      billStatus(bill(due: DateTime(2026, 10, 17)), now),
      BillStatus.dueSoon,
    );
    expect(
      billStatus(bill(due: DateTime(2026, 10, 24)), now),
      BillStatus.dueSoon,
    );
    expect(
      billStatus(bill(due: DateTime(2026, 10, 25)), now),
      BillStatus.later,
    );
    expect(
      billStatus(bill(due: DateTime(2026, 10, 16), active: false), now),
      BillStatus.paused,
    );
  });

  test('monthly totals are per currency and integer', () {
    final totals = monthlyTotals([
      bill(id: 'a', amount: 45000), // 45.000 TND
      bill(id: 'b', amount: 12000, cycle: BillCycle.yearly), // 1.000 / month
      bill(id: 'n', amount: 1599, currency: Currency.usd), // Netflix
      bill(id: 'p', amount: 99900, active: false), // paused: ignored
    ]);
    expect(totals[Currency.tnd], const Money.tnd(46000));
    expect(totals[Currency.usd], const Money.usd(1599));
    expect(totals.length, 2);
  });

  test('weekly and custom cycles are averaged to a month', () {
    // 12 per week -> 52 weeks / 12 months = 52 per month.
    expect(monthlyMinor(bill(amount: 12000, cycle: BillCycle.weekly)), 52000);
    // 30 every 30 days -> 365/12 payments a year-month = 30.417.
    expect(
      monthlyMinor(
        bill(amount: 30000, cycle: BillCycle.customDays, customDays: 30),
      ),
      30417,
    );
    expect(monthlyTotals(const []), isEmpty);
  });

  test('bills due within a week include overdue ones, soonest first', () {
    final list = billsDueWithin([
      bill(id: 'late', due: DateTime(2026, 11, 20)),
      bill(id: 'soon', due: DateTime(2026, 10, 22)),
      bill(id: 'over', due: DateTime(2026, 10, 10)),
      bill(id: 'off', due: DateTime(2026, 10, 18), active: false),
    ], now);
    expect(list.map((b) => b.id), ['over', 'soon']);
  });

  test('due labels', () {
    expect(dueLabel(DateTime(2026, 10, 14), now), 'Overdue by 3 days');
    expect(dueLabel(DateTime(2026, 10, 17), now), 'Due today');
    expect(dueLabel(DateTime(2026, 10, 18), now), 'Due tomorrow');
    expect(dueLabel(DateTime(2026, 10, 20), now), 'Due in 3 days');
    expect(dueLabel(DateTime(2026, 12, 2), now), 'Due 2 Dec 2026');
  });

  group('reminders', () {
    test('fires at 09:00, reminderDaysBefore days before the due date', () {
      expect(
        reminderTime(
          bill(due: DateTime(2026, 10, 20), remind: 3),
          DateTime(2026, 10, 1),
        ),
        DateTime(2026, 10, 17, 9),
      );
    });

    test('nothing for a past moment or a paused bill', () {
      expect(
        reminderTime(bill(due: DateTime(2026, 10, 19), remind: 3), now),
        isNull,
      );
      expect(reminderTime(bill(active: false), now), isNull);
    });

    test('stable positive ids', () {
      expect(reminderId('abc'), reminderId('abc'));
      expect(reminderId('abc'), isNot(reminderId('abd')));
      expect(reminderId('some-uuid-1234') >= 0, isTrue);
      expect(reminderId('some-uuid-1234') < 0x80000000, isTrue);
    });

    test('text', () {
      final t = reminderText(bill(id: 'STEG', amount: 45000, remind: 1));
      expect(t.title, 'STEG is due tomorrow');
      expect(t.body, '45.000 TND');
    });
  });
}
