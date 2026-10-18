import 'package:daftar/ui/core/widgets/collapsing_header.dart';
import 'package:daftar/ui/core/widgets/empty_state.dart';
import 'package:daftar/ui/core/widgets/floating_toast.dart';
import 'package:daftar/ui/core/widgets/glass_long_press_menu.dart';
import 'package:daftar/ui/core/widgets/skeleton.dart';
import 'package:daftar/ui/core/widgets/success_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  group('FloatingToast', () {
    testWidgets('appears, then leaves on its own; a new one replaces the old', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );

      FloatingToast.show(
        ctx,
        'Price saved',
        subtitle: 'Milka Oreo',
        kind: ToastKind.success,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Price saved'), findsOneWidget);
      expect(find.text('Milka Oreo'), findsOneWidget);

      FloatingToast.show(ctx, 'Second');
      await tester.pump();
      expect(find.text('Price saved'), findsNothing);
      expect(find.text('Second'), findsOneWidget);

      await tester.pump(FloatingToast.displayTime);
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsNothing);
    });

    testWidgets('action button runs and closes the toast', (tester) async {
      late BuildContext ctx;
      var undone = 0;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
          reduceMotion: true,
        ),
      );
      FloatingToast.show(
        ctx,
        'Deleted',
        actionLabel: 'Undo',
        onAction: () => undone++,
      );
      await tester.pump();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(find.text('Deleted'), findsNothing);
    });
  });

  group('GlassLongPressMenu', () {
    testWidgets(
      'long press opens the menu, tap runs the action, plain tap still works',
      (tester) async {
        var tapped = 0;
        var edited = 0;
        await tester.pumpWidget(
          testApp(
            Center(
              child: GlassLongPressMenu(
                onTap: () => tapped++,
                actions: [
                  GlassMenuAction(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    onTap: () => edited++,
                  ),
                  GlassMenuAction(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    onTap: () {},
                    destructive: true,
                  ),
                ],
                child: const SizedBox(
                  width: 200,
                  height: 56,
                  child: Text('Row'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Row'));
        expect(tapped, 1);

        await tester.longPress(find.text('Row'));
        await tester.pumpAndSettle();
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);

        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(edited, 1);
        expect(find.text('Edit'), findsNothing);
      },
    );

    testWidgets('tapping the dimmed background closes it without acting', (
      tester,
    ) async {
      var edited = 0;
      await tester.pumpWidget(
        testApp(
          Center(
            child: GlassLongPressMenu(
              actions: [
                GlassMenuAction(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: () => edited++,
                ),
              ],
              child: const SizedBox(width: 200, height: 56, child: Text('Row')),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Row'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsNothing);
      expect(edited, 0);
    });
  });

  group('CollapsingHeader', () {
    testWidgets('shrinks as the page scrolls and keeps the title', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          CustomScrollView(
            slivers: [
              const CollapsingHeader(
                title: 'Café El Houma',
                subtitle: 'Open now',
              ),
              SliverList.builder(
                itemCount: 30,
                itemBuilder: (_, i) =>
                    SizedBox(height: 80, child: Text('row $i')),
              ),
            ],
          ),
        ),
      );
      final headerBox = find.descendant(
        of: find.byType(CollapsingHeader),
        matching: find.byType(ClipRect),
      );
      final expanded = tester.getSize(headerBox).height;
      expect(find.text('Open now'), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final collapsed = tester.getSize(headerBox).height;
      expect(collapsed, lessThan(expanded));
      expect(find.text('Café El Houma'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leading and actions are tappable', (tester) async {
      var back = 0;
      await tester.pumpWidget(
        testApp(
          CustomScrollView(
            slivers: [
              CollapsingHeader(
                title: 'Place',
                leading: HeaderIconButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  onTap: () => back++,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byTooltip('Back'));
      expect(back, 1);
    });
  });

  group('Skeleton, EmptyState, SuccessCheck', () {
    testWidgets('Skeleton animates and is still with reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(testApp(const Skeleton(width: 100, height: 20)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Skeleton), findsOneWidget);

      await tester.pumpWidget(
        testApp(const SkeletonList(), reduceMotion: true),
      );
      await tester
          .pumpAndSettle(); // would time out if something kept animating
      expect(find.byType(Skeleton), findsNWidgets(20));
    });

    testWidgets('EmptyState shows message and action', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        testApp(
          Center(
            child: EmptyState(
              message: 'No places yet.',
              actionLabel: 'Add place',
              onAction: () => pressed++,
            ),
          ),
          reduceMotion: true,
          dark: false,
        ),
      );
      expect(find.text('No places yet.'), findsOneWidget);
      await tester.tap(find.text('Add place'));
      expect(pressed, 1);
    });

    testWidgets(
      'SuccessCheck calls onDone after the morph; immediately when reduced',
      (tester) async {
        var done = 0;
        await tester.pumpWidget(
          testApp(Center(child: SuccessCheck(onDone: () => done++))),
        );
        expect(done, 0);
        await tester.pumpAndSettle();
        expect(done, 1);

        var doneReduced = 0;
        await tester.pumpWidget(
          testApp(
            Center(
              child: SuccessCheck(
                key: const Key('r'),
                onDone: () => doneReduced++,
              ),
            ),
            reduceMotion: true,
          ),
        );
        await tester.pump();
        expect(doneReduced, 1);
      },
    );

    test('DalCheckPainter morphs from the Dal start to the check end', () {
      final start = DalCheckPainter.pointsAt(0);
      final end = DalCheckPainter.pointsAt(1);
      expect(start.first, const Offset(48, 32));
      expect(end.first, const Offset(34, 64));
      expect(end.last.dx, closeTo(90, 0.001));
      expect(end.last.dy, closeTo(40, 0.001));
      expect(DalCheckPainter.pointsAt(0.5).length, start.length);
    });
  });
}
