/// Granularity of an account summary.
enum SummaryGranularity { day, week, month, year }

/// One calendar period in the device's local time zone: `[start, end)`.
///
/// Built from calendar fields (never by adding 24 h), so day lengths of 23 / 25
/// hours around a clock change cannot shift a boundary. Weeks start on Monday.
class SummaryPeriod {
  const SummaryPeriod._(this.granularity, this.start, this.end);

  /// The period of [granularity] that contains [anchor] (read in local time).
  factory SummaryPeriod.containing(
    SummaryGranularity granularity,
    DateTime anchor,
  ) {
    final a = anchor.toLocal();
    final monday = a.day - (a.weekday - DateTime.monday);
    return switch (granularity) {
      SummaryGranularity.day => SummaryPeriod._(
        granularity,
        DateTime(a.year, a.month, a.day),
        DateTime(a.year, a.month, a.day + 1),
      ),
      SummaryGranularity.week => SummaryPeriod._(
        granularity,
        DateTime(a.year, a.month, monday),
        DateTime(a.year, a.month, monday + 7),
      ),
      SummaryGranularity.month => SummaryPeriod._(
        granularity,
        DateTime(a.year, a.month),
        DateTime(a.year, a.month + 1),
      ),
      SummaryGranularity.year => SummaryPeriod._(
        granularity,
        DateTime(a.year),
        DateTime(a.year + 1),
      ),
    };
  }

  final SummaryGranularity granularity;

  /// First instant of the period (local midnight), inclusive.
  final DateTime start;

  /// First instant after the period, exclusive.
  final DateTime end;

  SummaryPeriod get next => SummaryPeriod.containing(granularity, end);

  /// The period right before this one.
  SummaryPeriod get previous => SummaryPeriod.containing(
    granularity,
    DateTime(start.year, start.month, start.day - 1),
  );

  /// The period of granularity [g] that contains this period's start.
  SummaryPeriod withGranularity(SummaryGranularity g) =>
      SummaryPeriod.containing(g, start);

  /// True when [instant] falls inside the period.
  bool contains(DateTime instant) =>
      !instant.isBefore(start) && instant.isBefore(end);

  /// True when this period contains [now] or lies after it (no "next" then).
  bool isCurrentOrFuture(DateTime now) => end.isAfter(now);

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const _shortMonths = [
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

  /// "17 Oct 2026", "12 Oct – 18 Oct 2026", "October 2026", "2026".
  String get label {
    String day(DateTime d) => '${d.day} ${_shortMonths[d.month - 1]}';
    switch (granularity) {
      case SummaryGranularity.day:
        return '${day(start)} ${start.year}';
      case SummaryGranularity.week:
        final last = DateTime(end.year, end.month, end.day - 1);
        final left = start.year == last.year
            ? day(start)
            : '${day(start)} ${start.year}';
        return '$left – ${day(last)} ${last.year}';
      case SummaryGranularity.month:
        return '${_months[start.month - 1]} ${start.year}';
      case SummaryGranularity.year:
        return '${start.year}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SummaryPeriod &&
      other.granularity == granularity &&
      other.start == start;

  @override
  int get hashCode => Object.hash(granularity, start);

  @override
  String toString() => 'SummaryPeriod($granularity, $start)';
}
