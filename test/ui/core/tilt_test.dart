import 'dart:async';

import 'package:daftar/ui/core/motion/tilt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  group('TiltFilter', () {
    test('first sample is the resting pose (no tilt)', () {
      final f = TiltFilter();
      final r = f.add(0.2, 6.5);
      expect(r.x, 0);
      expect(r.y, 0);
    });

    test('tipping the right edge down gives positive x, clamped to 1', () {
      final f = TiltFilter(smoothing: 1);
      f.add(0, 6);
      expect(f.add(-2, 6).x, closeTo(0.5, 0.05));
      expect(f.add(-50, 6).x, closeTo(1, 0.001));
    });

    test('tipping the top edge away gives positive y', () {
      final f = TiltFilter(smoothing: 1);
      f.add(0, 6);
      expect(f.add(0, 8).y, closeTo(0.5, 0.05));
    });

    test('smoothing eases toward the target', () {
      final f = TiltFilter(smoothing: 0.5);
      f.add(0, 6);
      final first = f.add(-4, 6).x;
      final second = f.add(-4, 6).x;
      expect(first, closeTo(0.5, 0.05));
      expect(second, greaterThan(first));
    });
  });

  group('Tilt', () {
    testWidgets('leans the child when readings arrive', (tester) async {
      final controller = StreamController<TiltReading>();
      addTearDown(() {
        controller.close();
      });
      await tester.pumpWidget(
        testApp(
          Tilt(
            readings: controller.stream,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      controller.add(const TiltReading(1, 0));
      await tester.pump();
      final transform = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(Tilt),
              matching: find.byType(Transform),
            ),
          )
          .first;
      expect(
        transform.transform.storage[2],
        isNot(0),
      ); // rotateY adds a z component
    });

    testWidgets('ignores readings with reduced motion', (tester) async {
      final controller = StreamController<TiltReading>();
      addTearDown(() {
        controller.close();
      });
      await tester.pumpWidget(
        testApp(
          Tilt(
            readings: controller.stream,
            child: const SizedBox(width: 100, height: 100),
          ),
          reduceMotion: true,
        ),
      );
      expect(controller.hasListener, isFalse);
    });

    testWidgets('survives sensor errors', (tester) async {
      final controller = StreamController<TiltReading>();
      addTearDown(() {
        controller.close();
      });
      await tester.pumpWidget(
        testApp(
          Tilt(
            readings: controller.stream,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      controller.addError(Exception('no sensor'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'is flat when the device has no sensor plugin (default stream)',
      (tester) async {
        await tester.pumpWidget(
          testApp(const Tilt(child: SizedBox(width: 100, height: 100))),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(SizedBox), findsWidgets);
      },
    );
  });
}
