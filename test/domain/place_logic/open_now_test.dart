import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/place_logic/open_now.dart';
import 'package:flutter_test/flutter_test.dart';

OpeningHours hours(Map<String, List<List<String>>> days) =>
    OpeningHours.fromJson(days);

void main() {
  // 2026-10-19 is a Monday.
  final monday = DateTime(2026, 10, 19);
  DateTime at(int h, [int m = 0, int dayOffset = 0]) =>
      DateTime(monday.year, monday.month, monday.day + dayOffset, h, m);

  group('openStatusAt', () {
    test('unknown without hours', () {
      expect(openStatusAt(null, at(12)).state, OpenState.unknown);
      expect(
        openStatusAt(const OpeningHours({}), at(12)).state,
        OpenState.unknown,
      );
    });

    test('open inside a range, closed outside', () {
      final h = hours({
        'mon': [
          ['08:00', '13:00'],
          ['15:00', '22:00'],
        ],
        'tue': [
          ['08:00', '22:00'],
        ],
      });
      expect(
        openStatusAt(h, at(10)),
        OpenStatus(OpenState.open, nextChange: at(13)),
      );
      expect(
        openStatusAt(h, at(14)),
        OpenStatus(OpenState.closed, nextChange: at(15)),
      );
      expect(openStatusAt(h, at(7, 59)).state, OpenState.closed);
      expect(openStatusAt(h, at(8)).state, OpenState.open);
      // Close time is exclusive.
      expect(openStatusAt(h, at(13)).state, OpenState.closed);
    });

    test('closing soon within the last hour', () {
      final h = hours({
        'mon': [
          ['08:00', '22:00'],
        ],
      });
      expect(openStatusAt(h, at(21, 10)).state, OpenState.closingSoon);
      expect(openStatusAt(h, at(20, 59)).state, OpenState.open);
      expect(openStatusAt(h, at(21, 10)).isOpen, isTrue);
    });

    test('empty list means closed, missing day means unknown', () {
      final h = hours({
        'mon': [],
        'tue': [
          ['09:00', '17:00'],
        ],
      });
      final closed = openStatusAt(h, at(12));
      expect(closed.state, OpenState.closed);
      expect(closed.nextChange, at(9, 0, 1));
      // Wednesday is not in the map.
      expect(openStatusAt(h, at(12, 0, 2)).state, OpenState.unknown);
    });

    test('ranges past midnight carry into the next day', () {
      final h = hours({
        'mon': [
          ['22:00', '02:00'],
        ],
        'tue': [],
      });
      expect(openStatusAt(h, at(23)).state, OpenState.open);
      final after = openStatusAt(h, at(1, 0, 1));
      expect(after.state, OpenState.closingSoon);
      expect(after.nextChange, at(2, 0, 1));
      expect(openStatusAt(h, at(3, 0, 1)).state, OpenState.closed);
    });

    test('24:00 and equal times mean all day, and back-to-back days merge', () {
      final h = hours({
        'mon': [
          ['00:00', '24:00'],
        ],
        'tue': [
          ['00:00', '00:00'],
        ],
        'wed': [],
      });
      final s = openStatusAt(h, at(12));
      expect(s.state, OpenState.open);
      expect(s.nextChange, at(0, 0, 2));
    });

    test('invalid times are ignored', () {
      final h = hours({
        'mon': [
          ['8am', '25:00'],
        ],
      });
      expect(openStatusAt(h, at(10)).state, OpenState.closed);
    });
  });

  group('describeOpenStatus', () {
    final h = hours({
      'mon': [
        ['08:00', '22:00'],
      ],
      'tue': [
        ['08:00', '22:00'],
      ],
      'wed': [],
      'thu': [
        ['08:00', '22:00'],
      ],
    });

    test('open / closing soon', () {
      expect(
        describeOpenStatus(openStatusAt(h, at(12)), at(12)),
        'Open · until 22:00',
      );
      expect(
        describeOpenStatus(openStatusAt(h, at(21, 35)), at(21, 35)),
        'Closes in 25 min',
      );
    });

    test('closed with next opening', () {
      expect(
        describeOpenStatus(openStatusAt(h, at(6)), at(6)),
        'Closed · opens 08:00',
      );
      expect(
        describeOpenStatus(openStatusAt(h, at(23)), at(23)),
        'Closed · opens tomorrow 08:00',
      );
      expect(
        describeOpenStatus(openStatusAt(h, at(23, 0, 1)), at(23, 0, 1)),
        'Closed · opens Thu 08:00',
      );
    });

    test('unknown', () {
      expect(
        describeOpenStatus(const OpenStatus(OpenState.unknown), at(12)),
        'Hours not set',
      );
    });
  });

  test('parseHm / formatHm', () {
    expect(parseHm('08:30'), 510);
    expect(parseHm('24:00'), 1440);
    expect(parseHm('24:01'), isNull);
    expect(parseHm('nope'), isNull);
    expect(formatHm(510), '08:30');
  });
}
