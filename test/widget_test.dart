import 'package:daftar/app/app.dart';
import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/ui/core/brand/dal_mark.dart';
import 'package:daftar/ui/features/home/view_models/home_summary.dart';
import 'package:daftar/ui/features/home/view_models/home_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app on an in-memory database, with "Remove animations" on so looping
/// motion (empty-state float, skeleton shimmer) lets `pumpAndSettle` finish.
Future<void> pumpApp(WidgetTester tester) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        homeSummaryProvider.overrideWithValue(const AsyncData(HomeSummary())),
      ],
      child: const DaftarApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('app boots on Home with the Dal mark and bottom nav', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('daftar'), findsOneWidget);
    expect(find.byType(DalMark), findsWidgets);
    expect(find.byTooltip('Quick add'), findsOneWidget);

    // Unmount inside the test so Drift's stream-close timer fires before teardown.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('nav switches to the Map tab', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Map'), findsWidgets);

    // Unmount inside the test so Drift's stream-close timer fires before teardown.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('DalWriteOn shows the full mark when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: DalWriteOn(color: Colors.white)),
        ),
      ),
    );
    await tester.pump();
    final mark = tester.widget<DalMark>(find.byType(DalMark));
    expect(mark.progress, 1);
  });
}
