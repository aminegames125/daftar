import '../models/bill.dart';
import '../models/money.dart';
import 'bill_schedule.dart';

/// Where a bill stands today.
enum BillStatus { overdue, dueSoon, later, paused }

/// A bill counts as "due soon" when it falls within this many days.
const int billDueSoonDays = 7;

BillStatus billStatus(Bill bill, DateTime now) {
  if (!bill.isActive) return BillStatus.paused;
  final days = daysUntilDue(bill.nextDueAt, now);
  if (days < 0) return BillStatus.overdue;
  if (days <= billDueSoonDays) return BillStatus.dueSoon;
  return BillStatus.later;
}

/// Integer division rounded to the nearest whole number (halves go up).
int _roundDiv(int numerator, int denominator) =>
    (numerator * 2 + denominator) ~/ (denominator * 2);

/// What one bill costs per month, in minor units (weekly = 52/12 payments a month,
/// custom = 365/days payments a year). Integer maths only.
int monthlyMinor(Bill bill) => switch (bill.cycle) {
  BillCycle.monthly => bill.amountMinor,
  BillCycle.yearly => _roundDiv(bill.amountMinor, 12),
  BillCycle.weekly => _roundDiv(bill.amountMinor * 52, 12),
  BillCycle.customDays => _roundDiv(
    bill.amountMinor * 365,
    12 * (bill.customDays ?? 30),
  ),
};

Map<Currency, Money> _byCurrency(Map<Currency, int> totals) => {
  for (final currency in Currency.values)
    if (totals.containsKey(currency))
      currency: Money(totals[currency]!, currency),
};

/// Monthly cost of the active bills, one total per currency (never mixed).
/// Currencies without bills are left out.
Map<Currency, Money> monthlyTotals(Iterable<Bill> bills) {
  final totals = <Currency, int>{};
  for (final b in bills) {
    if (!b.isActive) continue;
    totals[b.currency] = (totals[b.currency] ?? 0) + monthlyMinor(b);
  }
  return _byCurrency(totals);
}

/// Sum of [bills] per currency (what is due, not the monthly figure).
Map<Currency, Money> sumByCurrency(Iterable<Bill> bills) {
  final totals = <Currency, int>{};
  for (final b in bills) {
    totals[b.currency] = (totals[b.currency] ?? 0) + b.amountMinor;
  }
  return _byCurrency(totals);
}

/// Active bills overdue or due within [days] days, soonest first.
List<Bill> billsDueWithin(Iterable<Bill> bills, DateTime now, {int days = 7}) =>
    bills
        .where((b) => b.isActive && daysUntilDue(b.nextDueAt, now) <= days)
        .toList()
      ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));

/// "Overdue by 3 days", "Due today", "Due tomorrow", "Due in 5 days", "Due 12 Nov 2026".
String dueLabel(DateTime due, DateTime now) {
  final days = daysUntilDue(due, now);
  if (days < 0) {
    final n = -days;
    return n == 1 ? 'Overdue by 1 day' : 'Overdue by $n days';
  }
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days <= billDueSoonDays) return 'Due in $days days';
  return 'Due ${shortDate(due)}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "12 Nov 2026".
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
