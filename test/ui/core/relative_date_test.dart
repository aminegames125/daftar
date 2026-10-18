import 'package:daftar/ui/core/format/relative_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 16, 0, 10);

  test('today and yesterday use calendar days, not 24 h windows', () {
    expect(formatRelativeDate(DateTime(2026, 10, 16, 0, 1), now: now), 'today');
    expect(
      formatRelativeDate(DateTime(2026, 10, 15, 23, 50), now: now),
      'yesterday',
    );
  });

  test('a few days ago', () {
    expect(
      formatRelativeDate(DateTime(2026, 10, 13, 12), now: now),
      '3 days ago',
    );
    expect(formatRelativeDate(DateTime(2026, 9, 17), now: now), '29 days ago');
  });

  test('older dates are absolute; other years show the year', () {
    expect(formatRelativeDate(DateTime(2026, 3, 12), now: now), '12 Mar');
    expect(formatRelativeDate(DateTime(2025, 12, 1), now: now), '1 Dec 2025');
  });

  test('future dates fall back to today', () {
    expect(formatRelativeDate(DateTime(2026, 10, 20), now: now), 'today');
  });
}
