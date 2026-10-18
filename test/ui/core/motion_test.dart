import 'package:daftar/ui/core/motion/shake.dart';
import 'package:daftar/ui/core/motion/squish.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  group('Squish', () {
    testWidgets('calls onTap and presses in while the finger is down', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        testApp(
          Center(
            child: Squish(
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Squish)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });

    testWidgets('does not scale with reduced motion', (tester) async {
      await tester.pumpWidget(
        testApp(
          Center(
            child: Squish(
              onTap: () {},
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
          reduceMotion: true,
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Squish)),
      );
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.up();
    });

    testWidgets('ignores taps when disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        testApp(
          Center(
            child: Squish(
              enabled: false,
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Squish));
      expect(taps, 0);
    });
  });

  group('Shake', () {
    Widget host(int trigger, {bool reduce = false}) => testApp(
      Center(
        child: Shake(
          trigger: trigger,
          child: const SizedBox(key: Key('box'), width: 40, height: 40),
        ),
      ),
      reduceMotion: reduce,
    );

    testWidgets('moves sideways when the trigger changes, then settles', (
      tester,
    ) async {
      await tester.pumpWidget(host(0));
      final rest = tester.getTopLeft(find.byKey(const Key('box'))).dx;

      await tester.pumpWidget(host(1));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(find.byKey(const Key('box'))).dx, isNot(rest));

      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const Key('box'))).dx,
        closeTo(rest, 0.01),
      );
    });

    testWidgets('does not shake on first build or with reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(host(0, reduce: true));
      final rest = tester.getTopLeft(find.byKey(const Key('box'))).dx;
      await tester.pumpWidget(host(1, reduce: true));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(find.byKey(const Key('box'))).dx, rest);
    });
  });
}
