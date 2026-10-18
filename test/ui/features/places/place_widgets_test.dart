import 'package:daftar/domain/models/place.dart';
import 'package:daftar/ui/features/places/views/copy_chip.dart';
import 'package:daftar/ui/features/places/views/open_status_badge.dart';
import 'package:daftar/ui/features/places/views/opening_hours_editor.dart';
import 'package:daftar/ui/features/places/views/rating_stars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/test_app.dart';

void main() {
  group('RatingStars', () {
    testWidgets('tapping a star sets the rating; tapping it again clears it', (
      tester,
    ) async {
      int? rating;
      await tester.pumpWidget(
        testApp(
          StatefulBuilder(
            builder: (context, setState) => RatingStars(
              rating: rating,
              onChanged: (r) => setState(() => rating = r),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Not rated'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Rate 4'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(rating, 4);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
      expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Rated 4 of 5'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Rate 4'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(rating, isNull);
    });

    testWidgets('read-only stars ignore taps and work with reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const RatingStars(rating: 3, size: 20), reduceMotion: true),
      );
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
      await tester.tap(find.byIcon(Icons.star_rounded).first);
      await tester.pump();
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
    });

    testWidgets('interactive stars are 48 px targets', (tester) async {
      await tester.pumpWidget(
        testApp(RatingStars(rating: null, onChanged: (_) {})),
      );
      final box = tester.getSize(find.byType(GestureDetector).first);
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
    });
  });

  group('CopyChip', () {
    testWidgets('copies, shows Copied, then goes back', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        testApp(
          const Center(
            child: CopyChip(value: 'hunter2', label: 'Copy Wi-Fi'),
          ),
        ),
      );
      expect(find.text('Copy Wi-Fi'), findsOneWidget);

      await tester.tap(find.text('Copy Wi-Fi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied, 'hunter2');
      expect(find.text('Copied'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Copy Wi-Fi'), findsOneWidget);
    });
  });

  group('OpenStatusBadge', () {
    // Monday 2026-10-19 12:00.
    final noon = DateTime(2026, 10, 19, 12);
    const hours = OpeningHours({
      'mon': [(open: '08:00', close: '22:00')],
    });

    testWidgets('open now', (tester) async {
      await tester.pumpWidget(
        testApp(OpenStatusBadge(hours: hours, now: noon, chip: true)),
      );
      expect(find.text('Open · until 22:00'), findsOneWidget);
    });

    testWidgets('closed, with the next opening', (tester) async {
      await tester.pumpWidget(
        testApp(OpenStatusBadge(hours: hours, now: DateTime(2026, 10, 19, 23))),
      );
      expect(find.textContaining('Closed'), findsOneWidget);
    });

    testWidgets('hidden without hours', (tester) async {
      await tester.pumpWidget(testApp(OpenStatusBadge(hours: null, now: noon)));
      expect(find.byType(Row), findsNothing);
    });
  });

  group('OpeningHoursEditor', () {
    testWidgets('toggling a day closes it; "Same every day" copies it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      final calls = <String>[];
      await tester.pumpWidget(
        testApp(
          SingleChildScrollView(
            child: OpeningHoursEditor(
              hours: const OpeningHours({
                'mon': [
                  (open: '08:00', close: '13:00'),
                  (open: '15:00', close: '22:00'),
                ],
                'tue': [],
              }),
              onDayChanged: (day, ranges) => calls.add('$day:${ranges.length}'),
              onCopyToAll: (day) => calls.add('all:$day'),
            ),
          ),
        ),
      );

      expect(find.text('08:00–13:00'), findsOneWidget);
      expect(find.text('15:00–22:00'), findsOneWidget);

      // Monday's switch is the first one; turning it off sends an empty list.
      await tester.tap(find.bySemanticsLabel('Mon open'));
      await tester.tap(find.text('Same every day').first);
      // Tuesday is closed: turning it on gives it the default range.
      await tester.tap(find.bySemanticsLabel('Tue open'));
      expect(calls, ['mon:0', 'all:mon', 'tue:1']);
    });
  });
}
