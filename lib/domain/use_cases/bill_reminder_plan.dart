import '../models/bill.dart';

/// Hour of the day (local time) reminders fire at.
const int billReminderHour = 9;

/// When to remind about [bill]: [Bill.reminderDaysBefore] days before the due date,
/// at 09:00 local time. Null when the bill is paused or that moment has already
/// passed (an overdue bill is shown in the app, not re-notified at every start).
DateTime? reminderTime(Bill bill, DateTime now) {
  if (!bill.isActive) return null;
  final due = bill.nextDueAt;
  final at = DateTime(
    due.year,
    due.month,
    due.day - bill.reminderDaysBefore,
    billReminderHour,
  );
  return at.isAfter(now) ? at : null;
}

/// Stable positive 31-bit notification id for a bill (FNV-1a of the id; Dart's
/// `String.hashCode` changes between runs).
int reminderId(String billId) {
  var h = 0x811c9dc5;
  for (final unit in billId.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// Text of the reminder notification.
({String title, String body}) reminderText(Bill bill) {
  final when = switch (bill.reminderDaysBefore) {
    0 => 'today',
    1 => 'tomorrow',
    final n => 'in $n days',
  };
  return (
    title: '${bill.name} is due $when',
    body: bill.amount.formatWithCode(),
  );
}
