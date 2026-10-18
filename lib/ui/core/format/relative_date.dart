/// "Seen" style dates: relative when
/// recent, absolute otherwise.
///
/// * same day → `today`, previous day → `yesterday`
/// * 2–29 days → `3 days ago`
/// * older → `12 Mar` (adds the year when it is not [now]'s year: `12 Mar 2025`)
///
/// Calendar days are compared in the local time zone, so 23:50 yesterday is
/// "yesterday" even at 00:10.
String formatRelativeDate(DateTime date, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toLocal();
  final d = date.toLocal();
  final days = DateTime(
    current.year,
    current.month,
    current.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;

  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 30) return '$days days ago';
  final label = '${d.day} ${_months[d.month - 1]}';
  return d.year == current.year ? label : '$label ${d.year}';
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
