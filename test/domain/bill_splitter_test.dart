import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/bill_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> minors(SplitResult r) => r.shares.values.map((m) => m.minor).toList();

void main() {
  const s = BillSplitter();

  group('equal', () {
    test('42.000 / 4 = 10.500 each', () {
      final r = s.splitEqually(
        total: const Money.tnd(42000),
        personIds: ['a', 'b', 'c', 'd'],
      );
      expect(minors(r), [10500, 10500, 10500, 10500]);
    });

    test('remainder distributed to first people, sums exact', () {
      final r = s.splitEqually(
        total: const Money.tnd(10000),
        personIds: ['a', 'b', 'c'],
      );
      expect(minors(r), [3334, 3333, 3333]);
      expect(r.sum, r.total);
    });

    test('total smaller than people count', () {
      final r = s.splitEqually(
        total: const Money.tnd(2),
        personIds: ['a', 'b', 'c'],
      );
      expect(minors(r), [1, 1, 0]);
    });

    test('zero total and single person', () {
      expect(minors(s.splitEqually(total: Money.zeroTnd, personIds: ['a'])), [
        0,
      ]);
      expect(
        minors(s.splitEqually(total: const Money.tnd(777), personIds: ['a'])),
        [777],
      );
    });

    test('invalid input', () {
      expect(
        () => s.splitEqually(total: const Money.tnd(1), personIds: []),
        throwsArgumentError,
      );
      expect(
        () => s.splitEqually(total: const Money.tnd(-1), personIds: ['a']),
        throwsArgumentError,
      );
      expect(
        () => s.splitEqually(total: const Money.tnd(1), personIds: ['a', 'a']),
        throwsArgumentError,
      );
      expect(
        () => s.splitEqually(
          total: const Money.tnd(1),
          personIds: ['a'],
          remainderPersonId: 'zz',
        ),
        throwsArgumentError,
      );
    });

    test('exhaustive: always sums exactly', () {
      for (var n = 1; n <= 12; n++) {
        for (final t in [0, 1, 49, 50, 999, 10000, 12345, 99999]) {
          for (final p in RoundingPolicy.values) {
            final r = s.splitEqually(
              total: Money.tnd(t),
              personIds: [for (var i = 0; i < n; i++) 'p$i'],
              policy: p,
            );
            expect(r.sum, Money.tnd(t), reason: 'n=$n t=$t $p');
            expect(
              r.shares.values.every((m) => m.minor >= 0),
              isTrue,
              reason: 'n=$n t=$t $p',
            );
          }
        }
      }
    });

    test('cash rounding: others multiples of 50, remainder person absorbs', () {
      final r = s.splitEqually(
        total: const Money.tnd(10000),
        personIds: ['a', 'b', 'c'],
        policy: RoundingPolicy.cash050,
        remainderPersonId: 'c',
      );
      // 3334/3333 -> 3350 each for a,b; c pays 3300
      expect(minors(r), [3350, 3350, 3300]);
      expect(r.remainderPersonId, 'c');
    });

    test('cash rounding defaults remainder to first person', () {
      final r = s.splitEqually(
        total: const Money.tnd(10000),
        personIds: ['a', 'b', 'c'],
        policy: RoundingPolicy.cash050,
      );
      expect(r.remainderPersonId, 'a');
      expect(minors(r), [3300, 3350, 3350]);
    });

    test('cash rounding never produces a negative remainder', () {
      final r = s.splitEqually(
        total: const Money.tnd(125),
        personIds: ['a', 'b', 'c', 'd', 'e'],
        policy: RoundingPolicy.cash050,
      );
      expect(r.sum, const Money.tnd(125));
      expect(r.shares.values.every((m) => m.minor >= 0), isTrue);
    });

    test('exact multiples stay unchanged under cash policy', () {
      final r = s.splitEqually(
        total: const Money.tnd(42000),
        personIds: ['a', 'b', 'c', 'd'],
        policy: RoundingPolicy.cash050,
      );
      expect(minors(r), [10500, 10500, 10500, 10500]);
    });
  });

  group('by item', () {
    const people = ['a', 'b', 'c'];

    test('private items and a shared one', () {
      final r = s.splitByItem(
        personIds: people,
        items: [
          const SplitItem(id: '1', price: Money.tnd(8000), ownerIds: ['a']),
          const SplitItem(id: '2', price: Money.tnd(6000), ownerIds: ['b']),
          const SplitItem(
            id: '3',
            price: Money.tnd(9000),
            ownerIds: ['a', 'b', 'c'],
          ),
        ],
      );
      expect(minors(r), [11000, 9000, 3000]);
      expect(r.total, const Money.tnd(23000));
    });

    test('shared item with odd millime is split deterministically', () {
      final r = s.splitByItem(
        personIds: people,
        items: [
          const SplitItem(
            id: '1',
            price: Money.tnd(1000),
            ownerIds: ['c', 'a'],
          ),
        ],
      );
      expect(minors(r), [500, 0, 500]);
      final r2 = s.splitByItem(
        personIds: people,
        items: [
          const SplitItem(
            id: '1',
            price: Money.tnd(1001),
            ownerIds: ['c', 'a'],
          ),
        ],
      );
      // owners ordered by participant order: a gets the extra millime
      expect(minors(r2), [501, 0, 500]);
    });

    test('duplicate owner entries count once', () {
      final r = s.splitByItem(
        personIds: people,
        items: [
          const SplitItem(id: '1', price: Money.tnd(900), ownerIds: ['a', 'a']),
        ],
      );
      expect(minors(r), [900, 0, 0]);
    });

    test('tax and tip proportional with exact sums', () {
      final r = s.splitByItem(
        personIds: ['a', 'b'],
        items: [
          const SplitItem(id: '1', price: Money.tnd(10000), ownerIds: ['a']),
          const SplitItem(id: '2', price: Money.tnd(30000), ownerIds: ['b']),
        ],
        tax: BillSplitter.percentOf(const Money.tnd(40000), 1900),
        tip: const Money.tnd(1001),
      );
      // tax 7600 -> 1900 / 5700 ; tip 1001 -> 250.25 / 750.75 -> 250/751
      expect(minors(r), [10000 + 1900 + 250, 30000 + 5700 + 751]);
      expect(r.total, const Money.tnd(40000 + 7600 + 1001));
      expect(r.sum, r.total);
    });

    test('largest remainder gives leftover to biggest fraction', () {
      final r = s.splitByItem(
        personIds: ['a', 'b', 'c'],
        items: [
          const SplitItem(id: '1', price: Money.tnd(1000), ownerIds: ['a']),
          const SplitItem(id: '2', price: Money.tnd(1000), ownerIds: ['b']),
          const SplitItem(id: '3', price: Money.tnd(1000), ownerIds: ['c']),
        ],
        tip: const Money.tnd(100),
      );
      expect(minors(r), [1034, 1033, 1033]);
    });

    test('extras with no items are split equally', () {
      final r = s.splitByItem(
        personIds: people,
        items: [],
        tip: const Money.tnd(10),
      );
      expect(minors(r), [4, 3, 3]);
      expect(r.total, const Money.tnd(10));
    });

    test('person with no items pays no tax share', () {
      final r = s.splitByItem(
        personIds: people,
        items: [
          const SplitItem(id: '1', price: Money.tnd(5000), ownerIds: ['a']),
        ],
        tax: const Money.tnd(500),
      );
      expect(minors(r), [5500, 0, 0]);
    });

    test('cash rounding by item keeps the exact total', () {
      final r = s.splitByItem(
        personIds: people,
        items: [
          const SplitItem(id: '1', price: Money.tnd(7333), ownerIds: ['a']),
          const SplitItem(id: '2', price: Money.tnd(4111), ownerIds: ['b']),
          const SplitItem(
            id: '3',
            price: Money.tnd(5557),
            ownerIds: ['a', 'b', 'c'],
          ),
        ],
        tip: const Money.tnd(1234),
        policy: RoundingPolicy.cash050,
        remainderPersonId: 'b',
      );
      expect(r.sum, r.total);
      expect(r.total, const Money.tnd(7333 + 4111 + 5557 + 1234));
      expect(r.shares['a']!.minor % 50, 0);
      expect(r.shares['c']!.minor % 50, 0);
    });

    test('invalid input', () {
      expect(
        () => s.splitByItem(
          personIds: people,
          items: [const SplitItem(id: '1', price: Money.tnd(1), ownerIds: [])],
        ),
        throwsArgumentError,
      );
      expect(
        () => s.splitByItem(
          personIds: people,
          items: [
            const SplitItem(id: '1', price: Money.tnd(1), ownerIds: ['x']),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => s.splitByItem(personIds: [], items: []),
        throwsArgumentError,
      );
      expect(
        () => s.splitByItem(
          personIds: people,
          items: [],
          tip: const Money.tnd(-1),
        ),
        throwsArgumentError,
      );
    });

    test('exhaustive-ish: sums exact for many shapes', () {
      for (var tip = 0; tip < 400; tip += 37) {
        for (final p in RoundingPolicy.values) {
          final r = s.splitByItem(
            personIds: people,
            items: [
              const SplitItem(
                id: '1',
                price: Money.tnd(3331),
                ownerIds: ['a', 'b'],
              ),
              const SplitItem(
                id: '2',
                price: Money.tnd(1777),
                ownerIds: ['b', 'c'],
              ),
              const SplitItem(id: '3', price: Money.tnd(1), ownerIds: ['c']),
            ],
            tax: Money.tnd(tip * 3),
            tip: Money.tnd(tip),
            policy: p,
          );
          expect(r.sum, r.total);
        }
      }
    });
  });

  test('percentOf rounds half up', () {
    expect(
      BillSplitter.percentOf(const Money.tnd(1000), 1000),
      const Money.tnd(100),
    );
    expect(
      BillSplitter.percentOf(const Money.tnd(5), 1000),
      const Money.tnd(1),
    ); // 0.5 -> 1
    expect(
      BillSplitter.percentOf(const Money.tnd(4), 1000),
      const Money.tnd(0),
    );
  });
}
