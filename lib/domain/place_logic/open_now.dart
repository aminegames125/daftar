import '../models/place.dart';

/// Weekday keys of `OpeningHours.days`, Monday first (matches `DateTime.weekday - 1`).
const weekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

enum OpenState {
  /// No hours entered (or none for today).
  unknown,
  open,

  /// Open, but closes within [openStatusAt]'s `closingSoon` window.
  closingSoon,
  closed,
}

/// Result of [openStatusAt]. [nextChange] is when it opens (if closed) or
/// closes (if open); null when unknown or it never changes within a week.
class OpenStatus {
  const OpenStatus(this.state, {this.nextChange});

  final OpenState state;
  final DateTime? nextChange;

  bool get isOpen => state == OpenState.open || state == OpenState.closingSoon;

  @override
  bool operator ==(Object other) =>
      other is OpenStatus &&
      other.state == state &&
      other.nextChange == nextChange;

  @override
  int get hashCode => Object.hash(state, nextChange);

  @override
  String toString() => 'OpenStatus($state, $nextChange)';
}

/// Parses "08:00" (also "24:00") into minutes since midnight; null if invalid.
int? parseHm(String text) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  final h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  if (min > 59 || h > 24 || (h == 24 && min != 0)) return null;
  return h * 60 + min;
}

/// Formats minutes since midnight as "08:00".
String formatHm(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

typedef _Interval = ({DateTime start, DateTime end});

/// Whether the place is open at [now] (device local time, DATA_MODEL § 5).
///
/// * `null` hours, or an empty map → unknown.
/// * A day that is missing from the map is unknown; an empty list means closed.
/// * A range whose close is not after its open runs past midnight
///   ("22:00"–"02:00"); equal times mean open all day.
OpenStatus openStatusAt(
  OpeningHours? hours,
  DateTime now, {
  Duration closingSoon = const Duration(minutes: 60),
}) {
  if (hours == null || hours.days.isEmpty) {
    return const OpenStatus(OpenState.unknown);
  }

  // Intervals that could cover [now] or start after it: yesterday … a week ahead.
  final intervals = <_Interval>[];
  for (var offset = -1; offset <= 7; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    final ranges = hours.days[weekdayKeys[day.weekday - 1]];
    if (ranges == null) continue;
    for (final range in ranges) {
      final open = parseHm(range.open);
      final close = parseHm(range.close);
      if (open == null || close == null) continue;
      final end = close > open ? close : close + 24 * 60;
      intervals.add((
        start: DateTime(day.year, day.month, day.day, 0, open),
        end: DateTime(day.year, day.month, day.day, 0, end),
      ));
    }
  }
  intervals.sort((a, b) => a.start.compareTo(b.start));

  final current = intervals
      .where((i) => !i.start.isAfter(now) && i.end.isAfter(now))
      .firstOrNull;
  if (current != null) {
    // Merge back-to-back ranges (e.g. 00:00–24:00 followed by 00:00–24:00).
    var end = current.end;
    for (final i in intervals) {
      if (!i.start.isAfter(end) && i.end.isAfter(end)) end = i.end;
    }
    final soon = end.difference(now) <= closingSoon;
    return OpenStatus(
      soon ? OpenState.closingSoon : OpenState.open,
      nextChange: end,
    );
  }

  final today = hours.days[weekdayKeys[now.weekday - 1]];
  if (today == null) return const OpenStatus(OpenState.unknown);
  final next = intervals.where((i) => i.start.isAfter(now)).firstOrNull;
  return OpenStatus(OpenState.closed, nextChange: next?.start);
}

/// Short human text for a badge: "Open · until 22:00", "Closes in 25 min",
/// "Closed · opens 08:00" (today), "Closed · opens tomorrow 08:00", "Closed · opens Mon 08:00".
String describeOpenStatus(OpenStatus status, DateTime now) {
  String hm(DateTime t) => formatHm(t.hour * 60 + t.minute);
  final next = status.nextChange;
  switch (status.state) {
    case OpenState.unknown:
      return 'Hours not set';
    case OpenState.open:
      return next == null ? 'Open now' : 'Open · until ${hm(next)}';
    case OpenState.closingSoon:
      final mins = next == null
          ? 0
          : next.difference(now).inMinutes.clamp(1, 1 << 20);
      return 'Closes in $mins min';
    case OpenState.closed:
      if (next == null) return 'Closed';
      final today = DateTime(now.year, now.month, now.day);
      final days = DateTime(
        next.year,
        next.month,
        next.day,
      ).difference(today).inDays;
      final when = switch (days) {
        0 => '',
        1 => 'tomorrow ',
        _ => '${_dayLabel(next.weekday)} ',
      };
      return 'Closed · opens $when${hm(next)}';
  }
}

String _dayLabel(int weekday) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return labels[weekday - 1];
}
