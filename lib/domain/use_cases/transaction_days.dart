import '../models/account.dart';

/// Transactions that happened on one calendar day (local time).
class TransactionDay {
  const TransactionDay(this.day, this.transactions);

  /// Midnight of the day, local time.
  final DateTime day;

  /// Newest first.
  final List<AccountTransaction> transactions;
}

/// Groups [transactions] by local calendar day, newest day first and newest
/// transaction first inside a day.
List<TransactionDay> groupTransactionsByDay(
  Iterable<AccountTransaction> transactions,
) {
  final sorted = [...transactions]
    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  final days = <TransactionDay>[];
  for (final t in sorted) {
    final local = t.occurredAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (days.isNotEmpty && days.last.day == day) {
      days.last.transactions.add(t);
    } else {
      days.add(TransactionDay(day, [t]));
    }
  }
  return days;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Today", "Yesterday", else "12 Mar" (year added when not the current one).
String dayHeading(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${day.day} ${_months[day.month - 1]}';
  return day.year == now.year ? base : '$base ${day.year}';
}
