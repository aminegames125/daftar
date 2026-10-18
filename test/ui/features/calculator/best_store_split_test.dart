import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/prices_repository.dart';
import 'package:daftar/domain/models/basket.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/use_cases/basket_optimizer.dart';
import 'package:daftar/ui/features/calculator/view_models/best_store_view_model.dart';
import 'package:daftar/ui/features/calculator/view_models/calculator_providers.dart';
import 'package:daftar/ui/features/calculator/view_models/split_view_model.dart';
import 'package:daftar/ui/features/calculator/views/best_store_mode.dart';
import 'package:daftar/ui/features/calculator/views/split_mode.dart';
import 'package:daftar/ui/features/places/view_models/places_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../core/test_app.dart';

class _FakePrices implements PricesRepository {
  _FakePrices(this.offers);
  final Map<String, List<PriceEntry>> offers;

  @override
  Future<List<PriceEntry>> currentOffersForVariant(String variantId) async =>
      offers[variantId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _now = DateTime(2026, 10, 17);

PriceEntry _offer(String variant, String place, int millimes, {int ago = 1}) =>
    PriceEntry(
      id: '$variant-$place',
      variantId: variant,
      placeId: place,
      amount: Money.tnd(millimes),
      seenAt: _now.subtract(Duration(days: ago)),
    );

Place _place(String id, String name) =>
    Place(id: id, name: name, typeId: 'supermarket');

List<Override> _overrides(Map<String, List<PriceEntry>> offers) => [
  pricesRepositoryProvider.overrideWithValue(_FakePrices(offers)),
  placesProvider.overrideWith(
    (ref) => Stream.value([_place('a', 'Carrefour'), _place('b', 'Aziza')]),
  ),
];

BestStoreState _state({int skipped = 0}) {
  final opt = const BasketOptimizer().optimize(
    lines: const [
      BasketLine(key: 'v1', label: 'Milk', quantityMilli: 2000),
      BasketLine(key: 'v2', label: 'Bread'),
    ],
    prices: {
      'a': {
        'v1': const PriceQuote(Money.tnd(1500), ageDays: 2),
        'v2': const PriceQuote(Money.tnd(500), ageDays: 2),
      },
      'b': {'v1': const PriceQuote(Money.tnd(1400), ageDays: 120)},
    },
  );
  return BestStoreState(
    optimization: opt,
    placeNames: const {'a': 'Carrefour', 'b': 'Aziza'},
    itemNames: const {'v1': 'Milk', 'v2': 'Bread'},
    skippedCount: skipped,
  );
}

void main() {
  group('best store view model', () {
    test('buildPriceMap keeps newest quote per place and ignores globals', () {
      final map = buildPriceMap({
        'v1': [
          _offer('v1', 'a', 1000, ago: 3),
          PriceEntry(
            id: 'g',
            variantId: 'v1',
            globalTypeId: 't',
            amount: const Money.tnd(1),
            seenAt: _now,
          ),
        ],
      }, _now);
      expect(map.keys, ['a']);
      expect(map['a']!['v1']!.ageDays, 3);
    });

    test('basketLines skips hand-typed items', () {
      final basket = const Basket()
          .add(
            const BasketItem(
              id: '1',
              name: 'Milk',
              unitPrice: Money.tnd(1000),
              quantity: 3,
              variantId: 'v1',
            ),
          )
          .add(
            const BasketItem(
              id: '2',
              name: 'Typed',
              unitPrice: Money.tnd(1000),
            ),
          );
      final r = basketLines(basket);
      expect(r.skipped, 1);
      expect(r.lines.single.quantityMilli, 3000);
    });

    test('describeReason renders plain English', () {
      expect(describeReason(const CheapestTotalReason()), 'Cheapest total');
      expect(describeReason(const CoversAllReason(5)), 'Covers all 5 items');
      expect(
        describeReason(
          const NotWorthSecondTripReason(Money.tnd(400), Money.tnd(1000)),
        ),
        contains('not worth a second trip'),
      );
    });

    test('bestStoreProvider prices the basket via the repository', () async {
      final container = ProviderContainer(
        overrides: _overrides({
          'v1': [_offer('v1', 'a', 1000), _offer('v1', 'b', 900)],
        }),
      );
      addTearDown(container.dispose);
      container
          .read(basketProvider.notifier)
          .add(
            name: 'Milk',
            unitPrice: const Money.tnd(1000),
            quantity: 2,
            variantId: 'v1',
            productId: 'p1',
          );
      container.listen(bestStoreProvider, (_, _) {});
      await container.read(placesProvider.future);
      final s = await container.read(bestStoreProvider.future);
      expect(s.optimization.best!.placeId, 'b');
      expect(s.optimization.best!.total, const Money.tnd(1800));
      expect(s.placeName('b'), 'Aziza');
    });
  });

  group('Best store widget', () {
    Future<void> pump(
      WidgetTester tester,
      BestStoreState? state, {
      double scale = 1,
      bool emptyBasket = false,
    }) async {
      await tester.pumpWidget(
        testApp(
          const BestStoreMode(),
          textScale: scale,
          reduceMotion: true,
          overrides: [
            bestStoreProvider.overrideWith((ref) async => state ?? _state()),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BestStoreMode)),
      );
      if (!emptyBasket) {
        container
            .read(basketProvider.notifier)
            .add(
              name: 'Milk',
              unitPrice: const Money.tnd(1000),
              variantId: 'v1',
            );
      }
      await tester.pumpAndSettle();
    }

    testWidgets('empty basket', (tester) async {
      await pump(tester, null, emptyBasket: true);
      expect(find.textContaining('basket is empty'), findsOneWidget);
    });

    testWidgets('winner, reasons, runner-up and flags', (tester) async {
      await pump(tester, null);
      expect(find.text('Carrefour'), findsWidgets);
      expect(find.text('Covers all 2 items'), findsOneWidget);
      expect(find.text('Aziza'), findsWidgets);
      expect(find.textContaining('Missing: Bread'), findsOneWidget);
      expect(find.textContaining('Old price: Milk'), findsOneWidget);
    });

    testWidgets('no prices state', (tester) async {
      await pump(
        tester,
        const BestStoreState(
          optimization: BasketOptimization(stores: [], best: null, split: null),
          placeNames: {},
          itemNames: {'v1': 'Milk'},
          skippedCount: 0,
        ),
      );
      expect(find.textContaining('No place has a price'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('no overflow at 320 dp, text x$scale', (tester) async {
        tester.view.physicalSize = const Size(320, 640) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await pump(tester, _state(skipped: 2), scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('cheapest split card', () {
    testWidgets('shows lists, saving and the not-worth note', (tester) async {
      final opt = const BasketOptimizer().optimize(
        lines: const [
          BasketLine(key: 'v1', label: 'Milk'),
          BasketLine(key: 'v2', label: 'Bread'),
        ],
        prices: {
          'a': {
            'v1': const PriceQuote(Money.tnd(1000)),
            'v2': const PriceQuote(Money.tnd(600)),
          },
          'b': {
            'v1': const PriceQuote(Money.tnd(1200)),
            'v2': const PriceQuote(Money.tnd(500)),
          },
        },
      );
      expect(opt.split!.isWorthIt, isFalse);
      await tester.pumpWidget(
        testApp(
          const BestStoreMode(),
          reduceMotion: true,
          overrides: [
            bestStoreProvider.overrideWith(
              (ref) async => BestStoreState(
                optimization: opt,
                placeNames: const {'a': 'Carrefour', 'b': 'Aziza'},
                itemNames: const {'v1': 'Milk', 'v2': 'Bread'},
                skippedCount: 0,
              ),
            ),
          ],
        ),
      );
      ProviderScope.containerOf(tester.element(find.byType(BestStoreMode)))
          .read(basketProvider.notifier)
          .add(name: 'x', unitPrice: const Money.tnd(1), variantId: 'v1');
      await tester.pumpAndSettle();
      expect(find.text('Cheapest split'), findsOneWidget);
      expect(find.textContaining('not worth a second trip'), findsOneWidget);
      expect(find.textContaining('Extra saving'), findsOneWidget);
    });
  });

  group('split view model', () {
    final basket = const Basket()
        .add(
          const BasketItem(
            id: 'i1',
            name: 'Pizza',
            unitPrice: Money.tnd(10000),
          ),
        )
        .add(
          const BasketItem(id: 'i2', name: 'Soda', unitPrice: Money.tnd(2500)),
        );

    test('equal split of the basket total, remainder to first people', () {
      final o = computeSplit(const SplitState(people: 3), basket);
      expect(o.result!.total, const Money.tnd(12500));
      expect(o.result!.sum, const Money.tnd(12500));
      expect(o.result!.shares['p0'], const Money.tnd(4167));
      expect(o.result!.shares['p2'], const Money.tnd(4166));
    });

    test('typed amount with cash rounding keeps the exact total', () {
      final o = computeSplit(
        const SplitState(
          people: 3,
          source: SplitSource.typed,
          typedAmount: Money.tnd(10000),
          cashRounding: true,
          remainderIndex: 2,
        ),
        const Basket(),
      );
      final r = o.result!;
      expect(r.sum, const Money.tnd(10000));
      expect(r.shares['p0']!.minor % 50, 0);
      expect(r.remainderPersonId, 'p2');
    });

    test('hints when there is nothing to split', () {
      expect(computeSplit(const SplitState(), const Basket()).hint, isNotNull);
      expect(
        computeSplit(
          const SplitState(style: SplitStyle.byItem),
          const Basket(),
        ).result,
        isNull,
      );
    });

    test('by item with shared items and tax', () {
      const s = SplitState(
        style: SplitStyle.byItem,
        owners: {
          'i1': {0},
          'i2': {0, 1},
        },
        tax: Money.tnd(1000),
      );
      final o = computeSplit(s, basket);
      expect(o.result!.total, const Money.tnd(13500));
      expect(o.result!.sum, const Money.tnd(13500));
      expect(
        o.result!.shares['p0']!.minor > o.result!.shares['p1']!.minor,
        isTrue,
      );
    });

    test('notifier clamps people and toggles owners', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(splitProvider.notifier);
      n.setPeople(1);
      expect(c.read(splitProvider).people, 2);
      n.setPeople(99);
      expect(c.read(splitProvider).people, SplitState.maxPeople);
      n.setRemainder(15);
      n.setPeople(3);
      expect(c.read(splitProvider).remainderIndex, 2);
      n.toggleOwner('i1', 1);
      expect(effectiveOwners(c.read(splitProvider), 'i1'), [1]);
      n.shareWithAll('i1');
      expect(effectiveOwners(c.read(splitProvider), 'i1'), [0, 1, 2]);
    });
  });

  group('Split widget', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      double scale = 1,
    }) async {
      await tester.pumpWidget(
        testApp(const SplitMode(), textScale: scale, reduceMotion: true),
      );
      final c = ProviderScope.containerOf(
        tester.element(find.byType(SplitMode)),
      );
      c.read(basketProvider.notifier)
        ..add(
          name: 'A very long product name that wraps over lines',
          unitPrice: const Money.tnd(123457),
          quantity: 12,
        )
        ..add(name: 'Soda', unitPrice: const Money.tnd(2500));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('equal split shows the share and the rule', (tester) async {
      await pump(tester);
      expect(find.text('Each pays'), findsOneWidget);
      expect(find.textContaining('first people'), findsOneWidget);
    });

    testWidgets('people stepper and cash rounding update state', (
      tester,
    ) async {
      final c = await pump(tester);
      await tester.tap(find.bySemanticsLabel('One more person'));
      await tester.pump();
      expect(c.read(splitProvider).people, 3);
      await tester.tap(find.text('Round to 0.050 for cash'));
      await tester.pump();
      expect(c.read(splitProvider).cashRounding, isTrue);
      expect(find.textContaining('multiple of 0.050'), findsWidgets);
    });

    testWidgets('by item mode assigns people with chips', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.text('By item'));
      await tester.pumpAndSettle();
      expect(find.text('Who had what'), findsOneWidget);
      await tester.tap(find.text('P1').first);
      await tester.pump();
      expect(c.read(splitProvider).owners.values.first, {0});
    });

    for (final style in SplitStyle.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow at 320 dp, ${style.name}, text x$scale', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(320, 640) * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final c = await pump(tester, scale: scale);
          c.read(splitProvider.notifier)
            ..setStyle(style)
            ..setPeople(6)
            ..setCashRounding(true)
            ..setTax(const Money.tnd(1234));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
