import 'package:daftar/app/router.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/home/view_models/card_order.dart';
import 'package:daftar/ui/features/home/view_models/home_summary.dart';
import 'package:daftar/ui/features/home/view_models/home_view_model.dart';
import 'package:daftar/ui/features/home/views/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/money_card_overrides.dart';

class _FixedOrder extends HomeCardOrderController {
  _FixedOrder(this.initial);
  final List<HomeCardId> initial;

  @override
  List<HomeCardId> build() => initial;

  @override
  Future<void> move(int oldIndex, int newIndex) async {
    final next = [...state];
    next.insert(newIndex, next.removeAt(oldIndex));
    state = next;
  }
}

final _summary = HomeSummary(
  priceCount: 3,
  placeCount: 2,
  menuPlaceCount: 1,
  productCount: 1,
  recent: [
    RecentPrice(
      id: 'a',
      title: 'Milka Oreo 100 g',
      where: 'Store ABC',
      amount: const Money.tnd(4400),
      seenAt: DateTime.now().subtract(const Duration(days: 1)),
      productId: 'milka',
      placeId: 'p1',
      isMenu: false,
    ),
    RecentPrice(
      id: 'b',
      title: 'Capucin · S',
      where: 'Café El Houma',
      amount: const Money.tnd(2800),
      amountMax: const Money.tnd(3200),
      seenAt: DateTime.now().subtract(const Duration(days: 3)),
      placeId: 'p2',
      isMenu: true,
    ),
  ],
);

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    AsyncValue<HomeSummary>? summary,
    bool dark = true,
    bool reduce = true,
    double textScale = 1,
    Size size = const Size(412, 900),
    List<HomeCardId> order = HomeCardId.values,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: HomeScreen()),
        ),
        for (final path in [
          Routes.products,
          Routes.places,
          Routes.settings,
          Routes.scan,
          Routes.search,
          Routes.calculator,
        ])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text('screen $path')),
          ),
        GoRoute(
          path: '/products/:id',
          builder: (_, s) =>
              Scaffold(body: Text('product ${s.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/places/:id',
          builder: (_, s) =>
              Scaffold(body: Text('place ${s.pathParameters['id']}')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...moneyCardOverrides,
          homeSummaryProvider.overrideWithValue(summary ?? AsyncData(_summary)),
          homeCardOrderProvider.overrideWith(() => _FixedOrder(order)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduce,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
    'shows the wallet cards with counts, the latest price and the Recent list',
    (tester) async {
      await pumpHome(tester);

      for (final title in [
        'Prices',
        'Places',
        'Menus',
        'Calculator',
        'Accounts',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Soon'), findsNothing);
      expect(find.text('3 logged'), findsOneWidget);
      expect(find.text('2 saved'), findsOneWidget);
      expect(find.text('1 place'), findsOneWidget);
      expect(
        find.text('Latest · Milka Oreo 100 g · Store ABC'),
        findsOneWidget,
      );
      expect(find.text('4.400'), findsNWidgets(2)); // card + Recent row

      expect(find.text('Capucin · S'), findsOneWidget);
      expect(find.text('Café El Houma · 3 days ago'), findsOneWidget);
      expect(find.text('2.800–3.200'), findsOneWidget);
      expect(find.text('Store ABC · yesterday'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('light theme at 360 dp wide and 130% text has no overflow', (
    tester,
  ) async {
    await pumpHome(
      tester,
      dark: false,
      textScale: 1.3,
      size: const Size(360, 800),
    );
    expect(find.text('Prices'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty database shows the invitation to log the first price', (
    tester,
  ) async {
    await pumpHome(tester, summary: const AsyncData(HomeSummary()));
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('Tap + to log your first price'), findsOneWidget);
    expect(
      find.text('Nothing here yet. Tap + to log your first price.'),
      findsOneWidget,
    );
    expect(find.text('0 logged'), findsOneWidget);
  });

  testWidgets('loading shows skeletons and an error shows a message', (
    tester,
  ) async {
    await pumpHome(tester, summary: const AsyncLoading());
    expect(find.text('Prices'), findsOneWidget);
    expect(find.text('3 logged'), findsNothing);

    await pumpHome(
      tester,
      summary: AsyncError(Exception('boom'), StackTrace.empty),
    );
    expect(find.text('Could not load your prices.'), findsOneWidget);
  });

  testWidgets('cards open their screens', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Places'));
    await tester.pumpAndSettle();
    expect(find.text('screen ${Routes.places}'), findsOneWidget);

    await pumpHome(tester);
    await tester.tap(find.text('Menus'));
    await tester.pumpAndSettle();
    expect(find.text('screen ${Routes.places}'), findsOneWidget);

    await pumpHome(tester);
    await tester.tap(find.text('Prices'));
    await tester.pumpAndSettle();
    expect(find.text('screen ${Routes.products}'), findsOneWidget);

    await pumpHome(tester);
    await tester.tap(find.text('Calculator'));
    await tester.pumpAndSettle();
    expect(find.text('screen ${Routes.calculator}'), findsOneWidget);
  });

  testWidgets('settings, search and scan shortcuts', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('screen ${Routes.settings}'), findsOneWidget);

    await pumpHome(tester);
    await tester.tap(find.byTooltip('Scan barcode'));
    await tester.pumpAndSettle();
    expect(find.text('screen ${Routes.scan}'), findsOneWidget);

    await pumpHome(tester);
    await tester.tap(find.text('Search products, places, menus'));
    await tester.pumpAndSettle();
    expect(find.text('screen ${Routes.search}'), findsOneWidget);
  });

  testWidgets('Recent rows open the product or the place', (tester) async {
    await pumpHome(tester);
    await tester.scrollUntilVisible(
      find.text('Milka Oreo 100 g'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Milka Oreo 100 g'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milka Oreo 100 g'));
    await tester.pumpAndSettle();
    expect(find.text('product milka'), findsOneWidget);

    await pumpHome(tester);
    await tester.scrollUntilVisible(
      find.text('Capucin · S'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Capucin · S'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capucin · S'));
    await tester.pumpAndSettle();
    expect(find.text('place p2'), findsOneWidget);
  });

  testWidgets(
    'Edit opens the reorder list with every card; Done returns to the stack',
    (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(
        find.byIcon(Icons.drag_indicator_rounded),
        findsNWidgets(HomeCardId.values.length),
      );

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
    },
  );

  testWidgets(
    'a reordered wallet puts the first card in front (lowest on screen)',
    (tester) async {
      await pumpHome(
        tester,
        order: [
          HomeCardId.places,
          HomeCardId.prices,
          HomeCardId.menus,
          HomeCardId.calculator,
          HomeCardId.accounts,
        ],
      );
      final placesY = tester.getTopLeft(find.text('Places')).dy;
      final pricesY = tester.getTopLeft(find.text('Prices')).dy;
      final accountsY = tester.getTopLeft(find.text('Accounts')).dy;
      expect(placesY, greaterThan(pricesY));
      expect(pricesY, greaterThan(accountsY));
    },
  );

  testWidgets('the cards fan out when animations are on', (tester) async {
    await pumpHome(tester, reduce: false);
    final startY = tester.getTopLeft(find.text('Accounts')).dy;
    await tester.pump(const Duration(milliseconds: 1500));
    final endY = tester.getTopLeft(find.text('Accounts')).dy;
    expect(endY, lessThan(startY));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
