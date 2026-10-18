import 'package:daftar/domain/models/basket.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/features/calculator/view_models/basket_lookup.dart';
import 'package:daftar/ui/features/calculator/view_models/calculator_providers.dart';
import 'package:daftar/ui/features/calculator/views/calculator_screen.dart';
import 'package:daftar/ui/features/calculator/views/quantity_roll.dart';
import 'package:daftar/ui/features/products/view_models/catalog_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/test_app.dart';

/// A widget test with the semantics tree on (the keys are found by label).
void semanticTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  });
}

Future<void> setSize(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w, h) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

final _overrides = [
  productsProvider.overrideWith((ref) => Stream.value(const <Product>[])),
];

Future<ProviderContainer> pump(
  WidgetTester tester, {
  Widget screen = const CalculatorScreen(),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    testApp(
      screen,
      overrides: _overrides,
      textScale: textScale,
      reduceMotion: true,
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(screen.runtimeType)),
  );
}

Future<void> keys(WidgetTester tester, String labels) async {
  for (final ch in labels.split('')) {
    await tester.tap(
      find.bySemanticsLabel(RegExp('^${RegExp.escape(_name(ch))}\$')),
    );
    await tester.pump();
  }
}

String _name(String ch) => switch (ch) {
  '+' => 'Plus',
  '−' => 'Minus',
  '×' => 'Times',
  '÷' => 'Divided by',
  '%' => 'Percent',
  '.' => 'Decimal point',
  '=' => 'Equals',
  'C' => 'Clear',
  '0' => 'Zero',
  _ => ch,
};

void main() {
  group('Quick mode', () {
    semanticTest('types, evaluates live, keeps history on =', (tester) async {
      final container = await pump(tester);
      await keys(tester, '12+3.5');
      expect(find.text('15.500'), findsOneWidget);
      expect(find.text('12+3.5'), findsOneWidget);
      await keys(tester, '=');
      expect(container.read(quickCalcProvider).expression, '15.5');
      expect(container.read(quickCalcProvider).history, [
        const Money.tnd(15500),
      ]);
      // The history chip recalls a result.
      await keys(tester, 'C');
      expect(container.read(quickCalcProvider).expression, '');
      await tester.tap(find.bySemanticsLabel(RegExp('^Recall ')));
      await tester.pump();
      expect(container.read(quickCalcProvider).expression, '15.5');
    });

    semanticTest('shows an error for division by zero', (tester) async {
      await pump(tester);
      await keys(tester, '5÷0');
      expect(find.text('Cannot divide by zero'), findsOneWidget);
    });

    semanticTest('history keeps at most five results', (tester) async {
      final container = await pump(tester);
      for (final d in '1234567'.split('')) {
        await keys(tester, '$d=');
        await keys(tester, 'C');
      }
      expect(container.read(quickCalcProvider).history.length, 5);
      expect(container.read(quickCalcProvider).history.first.minor, 7000);
    });
  });

  group('Mode chips', () {
    semanticTest('switch modes and show the basket badge', (tester) async {
      final container = await pump(tester);
      expect(find.text('Quick'), findsOneWidget);
      await tester.tap(find.text('Best store'));
      await tester.pump();
      expect(container.read(calculatorModeProvider), CalculatorMode.bestStore);
      expect(find.textContaining('basket is empty'), findsOneWidget);
      await tester.tap(find.text('Split'));
      await tester.pump();
      expect(find.text('People'), findsOneWidget);

      container
          .read(basketProvider.notifier)
          .add(name: 'Milk', unitPrice: const Money.tnd(1300), quantity: 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('3'), findsOneWidget); // the badge
    });
  });

  group('Basket mode', () {
    semanticTest('quantity buttons update line and running totals', (
      tester,
    ) async {
      final container = await pump(tester);
      await tester.tap(find.text('Basket'));
      await tester.pump();
      expect(find.textContaining('Your basket is empty'), findsOneWidget);

      container
          .read(basketProvider.notifier)
          .add(name: 'Milk', unitPrice: const Money.tnd(1300));
      container
          .read(basketProvider.notifier)
          .add(name: 'Bread', unitPrice: const Money.tnd(250), quantity: 2);
      await tester.pump();
      expect(find.text('Total · 3 items'), findsOneWidget);
      expect(find.text('1.800'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('One more Milk'));
      await tester.pumpAndSettle();
      expect(container.read(basketProvider).total, const Money.tnd(3100));
      expect(find.text('Total · 4 items'), findsOneWidget);
      expect(find.byType(QuantityRoll), findsNWidgets(2));

      // Minus at quantity 1 becomes "remove".
      await tester.tap(find.bySemanticsLabel('One less Bread'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Remove Bread'));
      await tester.pumpAndSettle();
      expect(container.read(basketProvider).lineCount, 1);
    });

    semanticTest('add sheet adds a typed item', (tester) async {
      final container = await pump(tester);
      await tester.tap(find.text('Basket'));
      await tester.pump();
      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Eggs');
      await tester.enterText(find.byType(TextField).last, '4.2');
      await tester.tap(find.text('Add to basket'));
      await tester.pumpAndSettle();
      final basket = container.read(basketProvider);
      expect(basket.items.single.name, 'Eggs');
      expect(basket.total, const Money.tnd(4200));
    });
  });

  group('Pick mode', () {
    semanticTest('Insert pops the result', (tester) async {
      Money? picked;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    picked = await context.push<Money>('/pick'),
                child: const Text('Open'),
              ),
            ),
          ),
          GoRoute(
            path: '/pick',
            builder: (_, _) => const CalculatorScreen(pick: true),
          ),
        ],
      );
      await tester.pumpWidget(testRouterApp(router, overrides: _overrides));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Quick'), findsNothing); // no mode chips
      await keys(tester, '2×3.5');
      await tester.tap(find.text('Insert into price field'));
      await tester.pumpAndSettle();
      expect(picked, const Money.tnd(7000));
    });
  });

  group('No overflow', () {
    for (final (w, scale) in [(320.0, 1.0), (320.0, 2.0), (280.0, 2.0)]) {
      for (final mode in CalculatorMode.values) {
        semanticTest('${mode.label} at ${w.toInt()} dp, text x$scale', (
          tester,
        ) async {
          await setSize(tester, w, 640);
          final container = await pump(tester, textScale: scale);
          container.read(calculatorModeProvider.notifier).select(mode);
          container.read(basketProvider.notifier)
            ..add(
              name: 'A very long product name that wraps over lines',
              unitPrice: const Money.tnd(123456),
              quantity: 12,
            )
            ..setPlace(id: 'p', name: 'A rather long supermarket name here');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    semanticTest('long expression and history at 320 dp, text x2', (
      tester,
    ) async {
      await setSize(tester, 320, 640);
      final container = await pump(tester, textScale: 2);
      await keys(tester, '999999×999999');
      await keys(tester, '=');
      await keys(tester, '÷3');
      expect(container.read(quickCalcProvider).history, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    semanticTest('pick screen at 320 dp, text x2', (tester) async {
      await setSize(tester, 320, 640);
      await pump(
        tester,
        screen: CalculatorScreen(key: UniqueKey(), pick: true),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('basket_lookup', () {
    const milka = Product(
      id: 'p1',
      name: 'Milka',
      brand: 'Mondelez',
      variants: [
        Variant(id: 'v1', productId: 'p1', name: 'Oreo'),
        Variant(id: 'v2', productId: 'p1', name: 'Noisette'),
      ],
    );
    const milk = Product(
      id: 'p2',
      name: 'Délice milk',
      variants: [Variant(id: 'v3', productId: 'p2')],
    );

    test('searches variants, accent-insensitive; blank gives nothing', () {
      expect(searchCandidates([milka, milk], ''), isEmpty);
      expect(searchCandidates([milka, milk], 'delice').map((c) => c.label), [
        'Délice milk',
      ]);
      expect(searchCandidates([milka, milk], 'milka').map((c) => c.label), [
        'Milka · Noisette',
        'Milka · Oreo',
      ]);
    });

    PriceEntry offer(String id, String place, int minor) => PriceEntry(
      id: id,
      variantId: 'v1',
      placeId: place,
      amount: Money.tnd(minor),
      seenAt: DateTime(2026),
    );

    test('suggested price prefers the chosen place, else the cheapest', () {
      final offers = [offer('a', 'A', 5000), offer('b', 'B', 4000)];
      expect(suggestedPrice(offers, 'A'), const Money.tnd(5000));
      expect(suggestedPrice(offers, null), const Money.tnd(4000));
      expect(suggestedPrice(offers, 'Z'), const Money.tnd(4000));
      expect(suggestedPrice(const [], 'A'), isNull);
    });
  });

  test('Basket is exported for reuse', () {
    expect(const Basket().isEmpty, isTrue);
  });
}
