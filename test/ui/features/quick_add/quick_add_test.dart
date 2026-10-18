import 'package:daftar/app/router.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/quick_add/views/quick_add_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<GoRouter> pumpApp(WidgetTester tester, {bool reduce = false}) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showQuickAddSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
        for (final path in [
          Routes.logPrice,
          Routes.placeNew,
          Routes.scan,
          Routes.menuSnap,
        ])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text('screen $path')),
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: child!,
        ),
      ),
    );
    return router;
  }

  testWidgets('the four actions spring out of the + and each opens its route', (
    tester,
  ) async {
    final labels = {
      'Log price': Routes.logPrice,
      'Add place': Routes.placeNew,
      'Scan barcode': Routes.scan,
      'Snap a menu': Routes.menuSnap,
    };
    for (final MapEntry(key: label, value: route) in labels.entries) {
      await pumpApp(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final l in labels.keys) {
        expect(find.text(l), findsOneWidget);
      }
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('screen $route'), findsOneWidget, reason: label);
    }
  });

  testWidgets('× and the backdrop close the menu without navigating', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Close quick add').last);
    await tester.pumpAndSettle();
    expect(find.text('Log price'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Add place'), findsNothing);
  });

  testWidgets('works with reduced motion and in light theme', (tester) async {
    await pumpApp(tester, reduce: true);
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text('Snap a menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
