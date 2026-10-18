import '../models/place.dart';
import 'open_now.dart';

const _dayNames = {
  'mon': 'Mon',
  'tue': 'Tue',
  'wed': 'Wed',
  'thu': 'Thu',
  'fri': 'Fri',
  'sat': 'Sat',
  'sun': 'Sun',
};

String dayLabel(String key) => _dayNames[key] ?? key;

/// Starting point when the user turns hours on: every day 08:00-22:00.
OpeningHours defaultOpeningHours() => OpeningHours({
  for (final d in weekdayKeys) d: [(open: '08:00', close: '22:00')],
});

/// Returns [hours] with [day] replaced. `null` ranges = unknown (day removed),
/// an empty list = closed.
OpeningHours setDay(OpeningHours? hours, String day, List<TimeRange>? ranges) {
  final days = {...?hours?.days};
  if (ranges == null) {
    days.remove(day);
  } else {
    days[day] = ranges;
  }
  return OpeningHours(days);
}

/// Copies one day's ranges onto every day ("same hours all week").
OpeningHours copyDayToAll(OpeningHours hours, String day) {
  final ranges = hours.days[day];
  return OpeningHours({
    for (final d in weekdayKeys)
      if (ranges != null) d: [...ranges],
  });
}

/// "08:00-13:00, 15:00-22:00", or "Closed".
String formatRanges(List<TimeRange> ranges) => ranges.isEmpty
    ? 'Closed'
    : ranges.map((r) => '${r.open}–${r.close}').join(', ');

/// Hours grouped for display: consecutive days with the same hours are joined
/// ("Mon–Sat" / "08:00–22:00", "Sun" / "Closed"). Unknown days are skipped.
List<({String days, String hours})> groupHours(OpeningHours hours) {
  final groups = <({List<String> keys, String hours})>[];
  for (final key in weekdayKeys) {
    final ranges = hours.days[key];
    if (ranges == null) continue;
    final text = formatRanges(ranges);
    final last = groups.isEmpty ? null : groups.last;
    final adjacent =
        last != null &&
        weekdayKeys.indexOf(last.keys.last) == weekdayKeys.indexOf(key) - 1;
    if (last != null && adjacent && last.hours == text) {
      last.keys.add(key);
    } else {
      groups.add((keys: [key], hours: text));
    }
  }
  return [
    for (final g in groups)
      (
        days: g.keys.length == 1
            ? dayLabel(g.keys.first)
            : '${dayLabel(g.keys.first)}–${dayLabel(g.keys.last)}',
        hours: g.hours,
      ),
  ];
}

/// True when [ranges] has a valid, non-empty shape for the editor.
bool rangesAreValid(List<TimeRange> ranges) =>
    ranges.every((r) => parseHm(r.open) != null && parseHm(r.close) != null);
