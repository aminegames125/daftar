import '../models/bill.dart';

/// The due date after [from] for a bill cycle.
///
/// Monthly/yearly keep the calendar day, clamped to the month length
/// (31 Jan -> 28/29 Feb). Pass [anchorDay] (the original day of month) so a
/// clamped date returns to e.g. the 31st the next month instead of staying on 28.
/// Time of day is preserved; arithmetic uses calendar fields so DST is harmless.
DateTime nextDueDate(
  DateTime from,
  BillCycle cycle, {
  int? customDays,
  int? anchorDay,
}) {
  DateTime clamped(int y, int m, int day) {
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(
      y,
      m,
      day > last ? last : day,
      from.hour,
      from.minute,
      from.second,
      from.millisecond,
    );
  }

  DateTime plusDays(int days) => DateTime(
    from.year,
    from.month,
    from.day + days,
    from.hour,
    from.minute,
    from.second,
    from.millisecond,
  );

  switch (cycle) {
    case BillCycle.weekly:
      return plusDays(7);
    case BillCycle.customDays:
      assert(customDays != null && customDays > 0);
      return plusDays(customDays!);
    case BillCycle.monthly:
      return clamped(from.year, from.month + 1, anchorDay ?? from.day);
    case BillCycle.yearly:
      return clamped(from.year + 1, from.month, anchorDay ?? from.day);
  }
}

/// First due date strictly after [after], advancing from [due] (for bills left
/// unpaid for several cycles).
DateTime nextDueAfter(
  DateTime due,
  DateTime after,
  BillCycle cycle, {
  int? customDays,
}) {
  final anchor = due.day;
  var next = due;
  var guard = 0;
  while (!next.isAfter(after) && guard++ < 10000) {
    next = nextDueDate(next, cycle, customDays: customDays, anchorDay: anchor);
  }
  return next;
}

/// Whole calendar days from [now] until [due] (negative = overdue).
int daysUntilDue(DateTime due, DateTime now) {
  final a = DateTime.utc(now.year, now.month, now.day);
  final b = DateTime.utc(due.year, due.month, due.day);
  return b.difference(a).inDays;
}

/// True when the reminder window has opened (or the bill is overdue).
bool isReminderDue(Bill bill, DateTime now) =>
    bill.isActive &&
    daysUntilDue(bill.nextDueAt, now) <= bill.reminderDaysBefore;
