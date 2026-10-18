import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/prices/view_models/user_location.dart';
import 'package:daftar/ui/features/products/view_models/catalog_providers.dart';
import 'package:daftar/ui/features/products/view_models/product_detail_view_model.dart';
import 'package:daftar/ui/features/products/views/price_history_chart.dart';
import 'package:daftar/ui/features/products/views/product_detail_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final now = DateTime(2026, 10, 16, 12);

PriceEntry entry(
  String id,
  String placeId,
  int millimes,
  int daysAgo, {
  String variant = 'oreo',
}) => PriceEntry(
  id: id,
  variantId: variant,
  placeId: placeId,
  amount: Money.tnd(millimes),
  seenAt: now.subtract(Duration(days: daysAgo)),
);

const milka = Product(
  id: 'm',
  name: 'Milka',
  brand: 'Mondelez',
  variants: [
    Variant(
      id: 'oreo',
      productId: 'm',
      name: 'Oreo',
      sizeValue: 100,
      sizeUnit: SizeUnit.g,
    ),
    Variant(
      id: 'noisette',
      productId: 'm',
      name: 'Noisette',
      sizeValue: 100,
      sizeUnit: SizeUnit.g,
    ),
  ],
);

final history = <String, List<PriceEntry>>{
  'oreo': [
    entry('a2', 'abc', 4400, 3),
    entry('c1', 'cbc', 5500, 14),
    entry('k1', 'corner', 4900, 130),
    entry('a1', 'abc', 3900, 60),
  ],
  'noisette': [],
};

List<Override> overrides({Map<String, List<PriceEntry>>? data}) => [
  clockProvider.overrideWithValue(() => now),
  productsProvider.overrideWith((ref) => Stream.value([milka])),
  variantHistoryProvider.overrideWith(
    (ref, id) => Stream.value((data ?? history)[id] ?? const []),
  ),
  staleDaysProvider.overrideWith((ref) => Stream.value(90)),
  globalPriceTypesProvider.overrideWith(
    (ref) => Stream.value(const [
      GlobalPriceType(id: 'ref', name: 'Reference price'),
    ]),
  ),
  allPlacesProvider.overrideWith(
    (ref) => Stream.value(const [
      Place(id: 'abc', name: 'Store ABC', typeId: 't'),
      Place(id: 'cbc', name: 'Store CBC', typeId: 't'),
      Place(id: 'corner', name: 'Corner shop', typeId: 't'),
    ]),
  ),
  userLocationProvider.overrideWith((ref) async => null),
];

Widget app(
  String productId, {
  ThemeData? theme,
  List<Override>? extra,
  bool reduced = true,
  String? variantId,
}) {
  final router = GoRouter(
    initialLocation: '/products/$productId',
    routes: [
      GoRoute(
        path: '/products/:id',
        builder: (_, s) => ProductDetailScreen(
          productId: s.pathParameters['id']!,
          variantId: variantId,
        ),
      ),
      GoRoute(
        path: '/prices/new',
        builder: (_, s) => Scaffold(body: Text('LOG ${s.uri.query}')),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [...overrides(), ...?extra],
    child: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduced,
        size: const Size(390, 844),
      ),
      child: MaterialApp.router(
        routerConfig: router,
        theme: theme ?? AppTheme.dark(),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'shows the best option with reasons, other offers, stale fading and the chart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app('m'));
      await tester.pumpAndSettle();

      expect(find.text('Best option'), findsOneWidget);
      expect(find.text('Cheapest per 100 g'), findsOneWidget);
      expect(find.text('Seen 3 days ago'), findsOneWidget);
      expect(find.text('Store CBC'), findsWidgets);
      expect(find.text('Other offers'), findsOneWidget);

      // 130 days old at the corner shop: faded to 40% and labelled "old".
      expect(find.textContaining('old'), findsWidgets);
      final fade = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity == 0.4);
      expect(fade, isNotEmpty);

      // Price went from 3.900 to 4.400 at Store ABC.
      expect(find.textContaining('+13% since'), findsWidgets);
      expect(find.textContaining('▲'), findsWidgets);

      expect(find.byType(PriceHistoryChart), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('All prices'), findsOneWidget);
      expect(find.text('Log price'), findsOneWidget);
    },
  );

  testWidgets(
    'variant chips switch the variant; a variant without prices invites the first one',
    (tester) async {
      await tester.pumpWidget(app('m'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Noisette · 100 g'));
      await tester.pumpAndSettle();
      expect(find.text('No prices yet. Log the first one.'), findsOneWidget);
      expect(find.text('Best option'), findsNothing);
    },
  );

  testWidgets('Log price opens the form for this product and variant', (
    tester,
  ) async {
    await tester.pumpWidget(app('m'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log price'));
    await tester.pumpAndSettle();
    expect(find.textContaining('productId=m'), findsOneWidget);
    expect(find.textContaining('variantId=oreo'), findsOneWidget);
  });

  testWidgets('works in the light theme', (tester) async {
    await tester.pumpWidget(app('m', theme: AppTheme.light()));
    await tester.pumpAndSettle();
    expect(find.text('Best option'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown product says it is gone', (tester) async {
    await tester.pumpWidget(app('nope'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('This product is gone.'), findsOneWidget);
  });

  testWidgets('chart plays its draw-in unless animations are removed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app('m', reduced: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LineChart), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
