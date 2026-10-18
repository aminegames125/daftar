import 'package:daftar/app/routes/core_routes.dart';
import 'package:daftar/app/settings.dart';
import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/settings_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/core/widgets/empty_state.dart';
import 'package:daftar/ui/core/widgets/skeleton.dart';
import 'package:daftar/ui/features/home/view_models/card_order.dart';
import 'package:daftar/ui/features/home/view_models/home_summary.dart';
import 'package:daftar/ui/features/home/view_models/home_view_model.dart';
import 'package:daftar/ui/features/home/views/home_screen.dart';
import 'package:daftar/ui/features/lock/view_models/lock_controller.dart';
import 'package:daftar/ui/features/prices/view_models/user_location.dart';
import 'package:daftar/ui/features/search/view_models/search_view_model.dart';
import 'package:daftar/ui/features/search/views/search_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../core/money_card_overrides.dart';
import '../core/test_app.dart';
import '../features/lock/lock_screen_test.dart' show FakeLock;
import '../features/settings/memory_settings_repository.dart';

/// Sweeps key screens at three phone widths and two text scales: no overflow
/// in the data / empty / loading / error states, plus Android accessibility
/// guidelines at normal text.
const _widths = [280.0, 320.0, 412.0];
const _scales = [1.0, 2.0];

final _summary = HomeSummary(
  priceCount: 3,
  placeCount: 2,
  menuPlaceCount: 1,
  productCount: 1,
  recent: [
    RecentPrice(
      id: 'a',
      title: 'Milka Oreo 100 g with a very long name to force wrapping',
      where: 'Store ABC with a long name too',
      amount: const Money.tnd(4400),
      seenAt: DateTime.now().subtract(const Duration(days: 1)),
      productId: 'milka',
      placeId: 'p1',
      isMenu: false,
    ),
  ],
);

class _Order extends HomeCardOrderController {
  @override
  List<HomeCardId> build() => HomeCardId.values;
}

void main() {
  void size(WidgetTester t, double w) {
    t.view.physicalSize = Size(w, 640) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Widget home(AsyncValue<HomeSummary> s, double scale) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: HomeScreen()),
        ),
        GoRoute(path: '/:any', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/:a/:b', builder: (_, _) => const SizedBox()),
      ],
    );
    return testRouterApp(
      router,
      textScale: scale,
      overrides: [
        ...moneyCardOverrides,
        homeSummaryProvider.overrideWithValue(s),
        homeCardOrderProvider.overrideWith(_Order.new),
      ],
    );
  }

  for (final w in _widths) {
    for (final scale in _scales) {
      final tag = '${w.toInt()} dp, text x$scale';

      testWidgets('Home: data / empty / loading / error fit at $tag', (
        tester,
      ) async {
        size(tester, w);
        for (final s in <AsyncValue<HomeSummary>>[
          AsyncData(_summary),
          const AsyncData(HomeSummary()),
          const AsyncLoading(),
          AsyncError(Exception('boom'), StackTrace.empty),
        ]) {
          await tester.pumpWidget(home(s, scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$s');
        }
      });

      testWidgets('Settings fits at $tag', (tester) async {
        size(tester, w);
        final router = GoRouter(
          initialLocation: '/settings',
          routes: [...coreRoutes],
        );
        await tester.pumpWidget(
          testRouterApp(
            router,
            textScale: scale,
            overrides: [
              settingsRepositoryProvider.overrideWithValue(
                MemorySettingsRepository() as SettingsRepository,
              ),
              lockControllerProvider.overrideWith(() => FakeLock()),
              initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Search (hint state) fits at $tag', (tester) async {
        size(tester, w);
        final db = AppDatabase(NativeDatabase.memory(), DateTime.now);
        await tester.pumpWidget(
          testApp(
            const SearchScreen(),
            textScale: scale,
            reduceMotion: true,
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              userLocationProvider.overrideWith((ref) async => null),
              searchDebounceProvider.overrideWithValue(Duration.zero),
            ],
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await db.close();
        });
      });

      testWidgets('EmptyState + Skeleton fit at $tag', (tester) async {
        size(tester, w);
        await tester.pumpWidget(
          testApp(
            Column(
              children: [
                Expanded(
                  child: EmptyState(
                    message:
                        'No places yet. Add the first one, then log prices.',
                    actionLabel: 'Add a place right now',
                    onAction: () {},
                  ),
                ),
                const Skeleton(height: 40),
              ],
            ),
            textScale: scale,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('Home meets tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    size(tester, 360);
    await tester.pumpWidget(home(AsyncData(_summary), 1));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('a list of 1000 rows builds only what is on screen', (
    tester,
  ) async {
    size(tester, 360);
    var built = 0;
    await tester.pumpWidget(
      testApp(
        ListView.builder(
          itemCount: 1000,
          itemBuilder: (_, i) {
            built++;
            return ListTile(title: Text('Price $i'));
          },
        ),
      ),
    );
    expect(built, lessThan(40));
  });
}
