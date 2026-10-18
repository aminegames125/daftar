import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/basket_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';

PriceQuote q(int m, {int age = 0}) => PriceQuote(Money.tnd(m), ageDays: age);

void main() {
  const opt = BasketOptimizer();
  final lines = [
    const BasketLine.count('milk', count: 2),
    const BasketLine.count('bread'),
    const BasketLine.count('eggs'),
  ];

  test('empty basket gives nothing', () {
    final r = opt.optimize(
      lines: [],
      prices: {
        'A': {'milk': q(1000)},
      },
    );
    expect(r.best, isNull);
    expect(r.split, isNull);
    expect(r.stores, isEmpty);
  });

  test('no prices at all gives nothing', () {
    final r = opt.optimize(lines: lines, prices: {});
    expect(r.best, isNull);
    final r2 = opt.optimize(
      lines: lines,
      prices: {
        'A': {'other': q(5)},
      },
    );
    expect(r2.best, isNull);
  });

  test('lowest complete total wins with saving vs next', () {
    final r = opt.optimize(
      lines: lines,
      prices: {
        'A': {'milk': q(1500), 'bread': q(300), 'eggs': q(800)},
        'B': {'milk': q(1600), 'bread': q(350), 'eggs': q(900)},
      },
    );
    expect(r.best!.placeId, 'A');
    expect(r.best!.total, const Money.tnd(4100));
    expect(r.stores[1].total, const Money.tnd(4450));
    expect(r.best!.savingVersusNext, const Money.tnd(350));
    expect(r.best!.reasons.first, isA<CheapestTotalReason>());
    expect(r.best!.reasons.whereType<CoversAllReason>().single.count, 3);
    expect(r.best!.reasons.whereType<SavesVersusNextReason>(), hasLength(1));
  });

  test('complete store beats cheaper partial store', () {
    final r = opt.optimize(
      lines: lines,
      prices: {
        'A': {'milk': q(100)},
        'B': {'milk': q(1500), 'bread': q(300), 'eggs': q(800)},
      },
    );
    expect(r.best!.placeId, 'B');
    final a = r.stores[1];
    expect(a.isComplete, isFalse);
    expect(a.missingKeys, ['bread', 'eggs']);
    expect(a.reasons.whereType<MissingItemsReason>().single.count, 2);
    expect(a.savingVersusNext, isNull);
    expect(r.best!.savingVersusNext, isNull);
  });

  test('none complete: most lines covered wins, flagged', () {
    final r = opt.optimize(
      lines: lines,
      prices: {
        'A': {'milk': q(100)},
        'B': {'milk': q(5000), 'bread': q(300)},
      },
    );
    expect(r.best!.placeId, 'B');
    expect(r.best!.coveredCount, 2);
    expect(r.best!.missingKeys, ['eggs']);
    expect(r.best!.coverage, closeTo(2 / 3, 1e-9));
    expect(r.best!.reasons.whereType<CoversPartialReason>().single.covered, 2);
  });

  test('single store', () {
    final r = opt.optimize(
      lines: lines,
      prices: {
        'A': {'milk': q(1000), 'bread': q(300), 'eggs': q(800)},
      },
    );
    expect(r.best!.reasons.whereType<OnlyStoreReason>(), hasLength(1));
    expect(r.best!.reasons.whereType<CheapestTotalReason>(), isEmpty);
    expect(r.best!.savingVersusNext, isNull);
    expect(r.split!.storesUsed, 1);
    expect(r.split!.isWorthIt, isFalse);
    expect(r.split!.savingVersusBest, Money.zeroTnd);
  });

  test('tie broken by freshness then id; flagged as tied', () {
    final r = opt.optimize(
      lines: [const BasketLine.count('x')],
      prices: {
        'A': {'x': q(1000, age: 10)},
        'B': {'x': q(1000, age: 1)},
        'C': {'x': q(1000, age: 1)},
      },
    );
    expect(r.stores.map((s) => s.placeId), ['B', 'C', 'A']);
    expect(r.best!.reasons.whereType<TiedReason>(), hasLength(1));
    expect(r.best!.reasons.whereType<CheapestTotalReason>(), isEmpty);
    expect(r.best!.savingVersusNext, Money.zeroTnd);
  });

  test('age reasons and stale flags', () {
    final r = opt.optimize(
      lines: [const BasketLine.count('x'), const BasketLine.count('y')],
      prices: {
        'A': {'x': q(100, age: 2), 'y': q(100, age: 1)},
        'B': {'x': q(100, age: 200), 'y': q(100, age: 1)},
      },
      staleDays: 90,
    );
    final a = r.stores.firstWhere((s) => s.placeId == 'A');
    final b = r.stores.firstWhere((s) => s.placeId == 'B');
    expect(a.reasons.whereType<PricesAgeReason>().single.days, 2);
    expect(a.staleKeys, isEmpty);
    expect(b.staleKeys, ['x']);
    final st = b.reasons.whereType<StalePricesReason>().single;
    expect((st.count, st.oldestDays), (1, 200));
    // exactly at the threshold is not stale
    final r2 = opt.optimize(
      lines: [const BasketLine.count('x')],
      prices: {
        'A': {'x': q(100, age: 90)},
      },
      staleDays: 90,
    );
    expect(r2.best!.staleKeys, isEmpty);
  });

  test('fresh prices (age 0) have no age reason', () {
    final r = opt.optimize(
      lines: [const BasketLine.count('x')],
      prices: {
        'A': {'x': q(100)},
      },
    );
    expect(r.best!.reasons.whereType<PricesAgeReason>(), isEmpty);
  });

  group('quantities and rounding', () {
    test('lineTotal rounds half up and keeps millimes', () {
      expect(
        BasketOptimizer.lineTotal(const Money.tnd(4400), 1500),
        const Money.tnd(6600),
      );
      expect(
        BasketOptimizer.lineTotal(const Money.tnd(1), 500),
        const Money.tnd(1),
      ); // 0.5 -> 1
      expect(
        BasketOptimizer.lineTotal(const Money.tnd(1), 499),
        const Money.tnd(0),
      );
      expect(
        BasketOptimizer.lineTotal(const Money.tnd(3333), 333),
        const Money.tnd(1110),
      ); // 1109.889
      expect(
        BasketOptimizer.lineTotal(const Money.tnd(1250), 2000),
        const Money.tnd(2500),
      );
    });

    test('decimal quantity', () {
      final r = opt.optimize(
        lines: [const BasketLine(key: 'rice', quantityMilli: 2500)],
        prices: {
          'A': {'rice': q(1990)},
        },
      );
      expect(r.best!.total, const Money.tnd(4975));
    });

    test('duplicate keys merge quantities', () {
      final r = opt.optimize(
        lines: [
          const BasketLine.count('a'),
          const BasketLine(key: 'a', quantityMilli: 500),
        ],
        prices: {
          'A': {'a': q(1000)},
        },
      );
      expect(r.best!.total, const Money.tnd(1500));
      expect(r.best!.totalLines, 1);
    });

    test('non-positive quantity throws', () {
      expect(
        () => opt.optimize(
          lines: [const BasketLine(key: 'a', quantityMilli: 0)],
          prices: {},
        ),
        throwsArgumentError,
      );
    });

    test('store total equals sum of line totals', () {
      final r = opt.optimize(
        lines: [
          const BasketLine(key: 'a', quantityMilli: 333),
          const BasketLine(key: 'b', quantityMilli: 667),
        ],
        prices: {
          'A': {'a': q(3333), 'b': q(1111)},
        },
      );
      final s = r.best!;
      final sum = s.lineTotals.values.fold<int>(0, (a, m) => a + m.minor);
      expect(s.total.minor, sum);
      expect(sum, 1110 + 741);
    });
  });

  group('cheapest split', () {
    final prices = {
      'A': {'milk': q(1000), 'bread': q(500), 'eggs': q(900)},
      'B': {'milk': q(1200), 'bread': q(300), 'eggs': q(1000)},
    };
    test('buys each line where cheapest and reports the saving', () {
      final r = opt.optimize(
        lines: [
          const BasketLine.count('milk'),
          const BasketLine.count('bread'),
          const BasketLine.count('eggs'),
        ],
        prices: prices,
      );
      expect(r.best!.placeId, 'A'); // 2400 vs 2500
      final s = r.split!;
      expect(s.total, const Money.tnd(2200));
      expect(s.storesUsed, 2);
      expect(s.perStore['A'], const Money.tnd(1900));
      expect(s.perStore['B'], const Money.tnd(300));
      expect(s.savingVersusBest, const Money.tnd(200));
      expect(s.isWorthIt, isFalse); // below 1.000 default
      expect(s.reasons.single, isA<NotWorthSecondTripReason>());
    });

    test('configurable threshold', () {
      final r = opt.optimize(
        lines: [
          const BasketLine.count('milk'),
          const BasketLine.count('bread'),
          const BasketLine.count('eggs'),
        ],
        prices: prices,
        splitThreshold: const Money.tnd(200),
      );
      expect(r.split!.isWorthIt, isTrue); // exactly at threshold counts
      final reason = r.split!.reasons.single as SplitSavesReason;
      expect(reason.stores, 2);
      expect(reason.saving, const Money.tnd(200));
    });

    test('equal prices stick to the best store', () {
      final r = opt.optimize(
        lines: [const BasketLine.count('a'), const BasketLine.count('b')],
        prices: {
          'A': {'a': q(100), 'b': q(100)},
          'B': {'a': q(100), 'b': q(100)},
        },
      );
      expect(r.split!.storesUsed, 1);
      expect(r.split!.assignments.map((a) => a.placeId).toSet(), {'A'});
    });

    test('item priced nowhere is unpriced; partial best compares fairly', () {
      final r = opt.optimize(
        lines: [
          const BasketLine.count('a'),
          const BasketLine.count('b'),
          const BasketLine.count('c'),
        ],
        prices: {
          'A': {'a': q(1000), 'b': q(1000)},
          'B': {'a': q(100)},
        },
      );
      expect(r.best!.placeId, 'A');
      final s = r.split!;
      expect(s.unpricedKeys, ['c']);
      expect(s.total, const Money.tnd(1100));
      expect(s.savingVersusBest, const Money.tnd(900));
      expect(s.isWorthIt, isFalse); // saving 0.900 < 1.000
    });

    test('line totals with rounding are what get compared', () {
      final r = opt.optimize(
        lines: [const BasketLine(key: 'a', quantityMilli: 1500)],
        prices: {
          'A': {'a': q(1001)}, // 1501.5 -> 1502
          'B': {'a': q(1000)}, // 1500
        },
      );
      expect(r.best!.placeId, 'B');
      expect(r.split!.total, const Money.tnd(1500));
    });
  });
}
