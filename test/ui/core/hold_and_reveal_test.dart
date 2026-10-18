import 'dart:ui' as ui;

import 'package:daftar/ui/core/widgets/hold_to_confirm.dart';
import 'package:daftar/ui/core/widgets/theme_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  group('HoldToConfirm', () {
    testWidgets('fires only after the full hold', (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(
        testApp(
          Center(
            child: HoldToConfirm(
              label: 'Hold to hide',
              onConfirmed: () => confirmed++,
            ),
          ),
        ),
      );

      final press = await tester.startGesture(
        tester.getCenter(find.text('Hold to hide')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await press.up();
      await tester.pumpAndSettle();
      expect(confirmed, 0);

      final hold = await tester.startGesture(
        tester.getCenter(find.text('Hold to hide')),
      );
      await tester.pump(const Duration(milliseconds: 150)); // press registers
      await tester.pump(const Duration(milliseconds: 1000));
      expect(confirmed, 1);
      await hold.up();
      await tester.pumpAndSettle();
      expect(confirmed, 1); // only once
    });

    testWidgets(
      'screen readers get a long-press action instead of a timed hold',
      (tester) async {
        var confirmed = 0;
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          testApp(
            Center(
              child: HoldToConfirm(
                label: 'Hold to hide',
                onConfirmed: () => confirmed++,
              ),
            ),
          ),
        );
        tester.semantics.longPress(find.semantics.byLabel('Hold to hide'));
        await tester.pump();
        expect(confirmed, 1);
        handle.dispose();
      },
    );

    testWidgets(
      'showHoldToConfirm returns true after a hold and false on cancel',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          testApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showHoldToConfirm(
                  context,
                  title: 'Delete?',
                  message: 'Sure?',
                  label: 'Hold to delete',
                ),
                child: const Text('ask'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('ask'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(result, isFalse);

        await tester.tap(find.text('ask'));
        await tester.pumpAndSettle();
        final hold = await tester.startGesture(
          tester.getCenter(find.text('Hold to delete')),
        );
        await tester.pump(const Duration(milliseconds: 150)); // press registers
        await tester.pump(const Duration(milliseconds: 1000));
        await hold.up();
        await tester.pumpAndSettle();
        expect(result, isTrue);
      },
    );
  });

  group('Theme reveal', () {
    test('the hole grows from the origin until it covers the whole area', () {
      const size = Size(400, 800);
      const origin = Offset(100, 200);
      final radius = CircleHoleClipper.coverRadius(origin, size);
      expect(
        radius,
        closeTo(const Offset(300, 600).distance, 0.001),
      ); // farthest corner

      Path clip(double p) =>
          CircleHoleClipper(center: origin, progress: p).getClip(size);

      expect(clip(0).contains(origin), isTrue); // nothing cut out yet
      expect(clip(0.5).contains(origin), isFalse); // hole around the tap
      expect(
        clip(0.5).contains(const Offset(399, 799)),
        isTrue,
      ); // far corner still old theme
      for (final corner in const [
        Offset.zero,
        Offset(399, 0),
        Offset(0, 799),
        Offset(399, 799),
      ]) {
        expect(clip(1.02).contains(corner), isFalse, reason: '$corner');
      }
    });

    test('shouldReclip follows progress and origin', () {
      const a = CircleHoleClipper(center: Offset(1, 1), progress: 0.2);
      expect(
        a.shouldReclip(
          const CircleHoleClipper(center: Offset(1, 1), progress: 0.2),
        ),
        isFalse,
      );
      expect(
        a.shouldReclip(
          const CircleHoleClipper(center: Offset(1, 1), progress: 0.3),
        ),
        isTrue,
      );
      expect(
        a.shouldReclip(
          const CircleHoleClipper(center: Offset(2, 1), progress: 0.2),
        ),
        isTrue,
      );
    });

    testWidgets(
      'run applies the change straight away when animation is off or nothing can be captured',
      (tester) async {
        final controller = ThemeRevealController();
        addTearDown(controller.dispose);
        var applied = 0;
        await controller.run(
          origin: Offset.zero,
          animate: false,
          apply: () async => applied++,
        );
        await controller.run(
          origin: Offset.zero,
          animate: true,
          apply: () async => applied++,
        ); // no boundary mounted
        expect(applied, 2);
        expect(controller.frame.value, isNull);
      },
    );

    testWidgets(
      'the host draws the snapshot over the app and removes it when the reveal ends',
      (tester) async {
        final controller = ThemeRevealController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ThemeRevealHost(
              controller: controller,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        );
        expect(find.byType(RawImage), findsNothing);

        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawRect(const Rect.fromLTWH(0, 0, 4, 4), ui.Paint());
        late ui.Image image;
        await tester.runAsync(
          () async => image = await recorder.endRecording().toImage(4, 4),
        );

        controller.frame.value = RevealFrame(
          image: image,
          origin: const Offset(10, 10),
        );
        await tester.pump();
        expect(find.byType(RawImage), findsOneWidget);

        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.byType(RawImage), findsNothing);
        expect(controller.frame.value, isNull);
      },
    );
  });
}
