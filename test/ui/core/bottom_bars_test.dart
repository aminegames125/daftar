import 'package:daftar/ui/core/widgets/daftar_action_bar.dart';
import 'package:daftar/ui/core/widgets/daftar_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

const _tabs = [
  NavDestination(icon: Icons.home_rounded, label: 'Home'),
  NavDestination(icon: Icons.search_rounded, label: 'Search'),
  NavDestination(icon: Icons.map_outlined, label: 'Map'),
  NavDestination(icon: Icons.calculate_outlined, label: 'Calculator'),
];

void main() {
  Future<void> setSize(WidgetTester tester, double w, double h) async {
    tester.view.physicalSize = Size(w, h) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('DaftarNavBar + QuickAddFab', () {
    Widget shell({
      required int index,
      ValueChanged<int>? onSelect,
      VoidCallback? onAdd,
      double textScale = 1,
    }) => _Shell(
      index: index,
      onSelect: onSelect ?? (_) {},
      onAdd: onAdd ?? () {},
      textScale: textScale,
    );

    testWidgets('selects tabs and fires the lime +', (tester) async {
      var picked = -1;
      var added = 0;
      await tester.pumpWidget(
        shell(index: 0, onSelect: (i) => picked = i, onAdd: () => added++),
      );
      await tester.tap(find.byIcon(Icons.map_outlined));
      await tester.tap(find.byTooltip('Quick add'));
      expect(picked, 2);
      expect(added, 1);
    });

    for (final (w, scale) in [
      (320.0, 1.0),
      (320.0, 2.0),
      (360.0, 1.3),
      (412.0, 1.0),
      (280.0, 2.0),
    ]) {
      testWidgets('no overflow at ${w.toInt()} dp wide, text x$scale', (
        tester,
      ) async {
        await setSize(tester, w, 640);
        await tester.pumpWidget(shell(index: 3, textScale: scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The + sits inside the bar, centred.
        final fab = tester.getRect(find.byType(QuickAddFab));
        final bar = tester.getRect(find.byType(DaftarNavBar));
        expect(bar.contains(fab.center), isTrue);
        expect(fab.center.dx, closeTo(bar.center.dx, 1));
      });
    }
  });

  group('DaftarActionBar', () {
    Widget bar({
      double textScale = 1,
      List<ToolbarAction>? actions,
      ToolbarAction? primary,
    }) => _Detail(textScale: textScale, actions: actions, primary: primary);

    testWidgets('fires its actions', (tester) async {
      var called = 0;
      var logged = 0;
      await tester.pumpWidget(
        bar(
          actions: [
            ToolbarAction(
              icon: Icons.call_outlined,
              label: 'Call',
              onTap: () => called++,
            ),
          ],
          primary: ToolbarAction(
            icon: Icons.add_rounded,
            label: 'Log price',
            onTap: () => logged++,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.call_outlined));
      await tester.tap(find.text('Log price'));
      expect(called, 1);
      expect(logged, 1);
      expect(find.byTooltip('Call'), findsOneWidget);
    });

    for (final (w, scale) in [(320.0, 1.0), (320.0, 2.0), (280.0, 2.0)]) {
      testWidgets(
        'four icons and a long label fit at ${w.toInt()} dp, text x$scale',
        (tester) async {
          await setSize(tester, w, 640);
          await tester.pumpWidget(
            bar(
              textScale: scale,
              actions: [
                for (final i in [
                  Icons.call_outlined,
                  Icons.directions_outlined,
                  Icons.edit_outlined,
                  Icons.share_outlined,
                ])
                  ToolbarAction(icon: i, label: 'Action', onTap: () {}),
              ],
              primary: ToolbarAction(
                icon: Icons.add_rounded,
                label: 'Log a new price here',
                onTap: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.index,
    required this.onSelect,
    required this.onAdd,
    required this.textScale,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return testAppScaffold(
      textScale: textScale,
      scaffold: Scaffold(
        bottomNavigationBar: DaftarNavBar(
          destinations: _tabs,
          currentIndex: index,
          onSelect: onSelect,
          onAdd: onAdd,
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.textScale, this.actions, this.primary});
  final double textScale;
  final List<ToolbarAction>? actions;
  final ToolbarAction? primary;

  @override
  Widget build(BuildContext context) {
    return testAppScaffold(
      textScale: textScale,
      scaffold: Scaffold(
        extendBody: true,
        bottomNavigationBar: DaftarActionBar(
          actions: actions ?? const [],
          primary: primary,
        ),
      ),
    );
  }
}
