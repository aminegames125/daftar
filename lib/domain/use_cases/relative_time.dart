/// Friendly, English-only date wording: relative when
/// recent ("yesterday", "3 days ago"), absolute otherwise ("12 Mar").
///
/// Pure functions with an explicit `now`, so they are trivial to test.
library;

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

/// Whole calendar days between [seen] and [now] (never negative).
int ageInDays(DateTime seen, DateTime now) {
  final days = now.difference(seen).inDays;
  return days < 0 ? 0 : days;
}

/// "today", "yesterday", "3 days ago", "2 weeks ago", "4 months ago", "2 years ago".
String relativeAge(DateTime seen, DateTime now) {
  final days = ageInDays(seen, now);
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  if (days < 730) return '${days ~/ 30} months ago';
  return '${days ~/ 365} years ago';
}

/// "12 Mar" (the year is added when it is not the current one: "12 Mar 2025").
String shortDate(DateTime date, DateTime now) {
  final base = '${date.day} ${_months[date.month - 1]}';
  return date.year == now.year ? base : '$base ${date.year}';
}

/// "1.2 km" (one decimal, never "0 km").
String formatKm(double km) => '${km.toStringAsFixed(1)} km';
