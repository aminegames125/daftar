import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/period_summary.dart';
import 'package:daftar/domain/use_cases/summary_period.dart';
import 'package:flutter_test/flutter_test.dart';

SummaryPeriod _p(SummaryGranularity g, DateTime d) =>
    SummaryPeriod.containing(g, d);

var _n = 0;
AccountTransaction _tx(
  TransactionKind kind,
  int amount, {
  String account = 'a',
  Currency currency = Currency.tnd,
  DateTime? at,
  String? category,
  int? fee,
}) => AccountTransaction(
  id: 't${_n++}',
  accountId: account,
  kind: kind,
  amountMinor: amount,
  currency: currency,
  occurredAt: at ?? DateTime(2026, 10, 15, 12),
  categoryId: category,
  feeMinor: fee,
);

Account _acct(String id, {bool include = true}) => Account(
  id: id,
  name: id,
  kind: AccountKind.cash,
  currency: Currency.tnd,
  includeInTotals: include,
);

void main() {
  group('SummaryPeriod', () {
    test('day', () {
      final p = _p(SummaryGranularity.day, DateTime(2026, 10, 17, 23, 59));
      expect(p.start, DateTime(2026, 10, 17));
      expect(p.end, DateTime(2026, 10, 18));
      expect(p.label, '17 Oct 2026');
    });

    test('week starts on Monday (Sunday belongs to the week before)', () {
      // 2026-10-17 is a Saturday; its Monday is the 12th.
      final sat = _p(SummaryGranularity.week, DateTime(2026, 10, 17));
      expect(sat.start, DateTime(2026, 10, 12));
      expect(sat.end, DateTime(2026, 10, 19));
      expect(sat.label, '12 Oct – 18 Oct 2026');
      final sun = _p(SummaryGranularity.week, DateTime(2026, 10, 18, 23, 59));
      expect(sun.start, DateTime(2026, 10, 12));
      final mon = _p(SummaryGranularity.week, DateTime(2026, 10, 19));
      expect(mon.start, DateTime(2026, 10, 19));
    });

    test('week across a month and a year boundary', () {
      final w = _p(SummaryGranularity.week, DateTime(2026, 1, 1)); // Thursday
      expect(w.start, DateTime(2025, 12, 29));
      expect(w.end, DateTime(2026, 1, 5));
      expect(w.label, '29 Dec 2025 – 4 Jan 2026');
    });

    test('month lengths incl. leap February and December', () {
      final feb = _p(SummaryGranularity.month, DateTime(2024, 2, 29, 23));
      expect(feb.start, DateTime(2024, 2));
      expect(feb.end, DateTime(2024, 3));
      final dec = _p(SummaryGranularity.month, DateTime(2026, 12, 31));
      expect(dec.end, DateTime(2027));
      expect(dec.label, 'December 2026');
    });

    test('year', () {
      final y = _p(SummaryGranularity.year, DateTime(2026, 6, 6));
      expect(y.start, DateTime(2026));
      expect(y.end, DateTime(2027));
      expect(y.label, '2026');
    });

    test('previous and next are adjacent for every granularity', () {
      for (final g in SummaryGranularity.values) {
        final p = _p(g, DateTime(2026, 3, 1)); // after a clock-change month
        expect(p.previous.end, p.start, reason: '$g');
        expect(p.next.start, p.end, reason: '$g');
        expect(p.next.previous, p);
        expect(p.previous.next, p);
      }
      expect(
        _p(SummaryGranularity.month, DateTime(2026, 1, 10)).previous.start,
        DateTime(2025, 12),
      );
    });

    test('boundaries are half-open, in local time', () {
      final p = _p(SummaryGranularity.month, DateTime(2026, 10, 15));
      expect(p.contains(DateTime(2026, 10, 1)), isTrue);
      expect(p.contains(DateTime(2026, 9, 30, 23, 59, 59, 999)), isFalse);
      expect(p.contains(DateTime(2026, 10, 31, 23, 59, 59, 999)), isTrue);
      expect(p.contains(DateTime(2026, 11, 1)), isFalse);
    });

    test('a UTC instant is placed by its absolute time', () {
      final p = _p(SummaryGranularity.day, DateTime(2026, 10, 15));
      expect(p.contains(p.start.toUtc()), isTrue);
      expect(p.contains(p.end.toUtc()), isFalse);
      // Re-anchoring with a UTC value reads it in local time.
      expect(_p(SummaryGranularity.day, p.start.toUtc()), p);
    });

    test('withGranularity keeps the start and isCurrentOrFuture works', () {
      final m = _p(SummaryGranularity.month, DateTime(2026, 10, 15));
      expect(m.withGranularity(SummaryGranularity.year).start, DateTime(2026));
      expect(m.isCurrentOrFuture(DateTime(2026, 10, 31, 23)), isTrue);
      expect(m.isCurrentOrFuture(DateTime(2026, 11, 1)), isFalse);
    });
  });

  group('summarizePeriod', () {
    final period = _p(SummaryGranularity.month, DateTime(2026, 10, 15));
    final accounts = [_acct('a'), _acct('b'), _acct('hidden', include: false)];

    PeriodSummary run(List<AccountTransaction> txs, {RateEntry? rate}) =>
        summarizePeriod(
          period: period,
          transactions: txs,
          accounts: accounts,
          rate: rate,
        );

    test('empty period', () {
      final s = run(const []);
      expect(s.isEmpty, isTrue);
      expect(s.tnd.net, const Money.tnd(0));
      expect(s.tnd.categories, isEmpty);
      expect(s.allInTnd, isNull);
    });

    test('income, spending and net per currency', () {
      final s = run([
        _tx(TransactionKind.income, 500000),
        _tx(TransactionKind.expense, 120500),
        _tx(TransactionKind.expense, 4500, account: 'b'),
        _tx(TransactionKind.income, 20000, currency: Currency.usd),
        _tx(TransactionKind.expense, 1250, currency: Currency.usd),
      ]);
      expect(s.tnd.income, const Money.tnd(500000));
      expect(s.tnd.spending, const Money.tnd(125000));
      expect(s.tnd.net, const Money.tnd(375000));
      expect(s.usd.income, const Money.usd(20000));
      expect(s.usd.spending, const Money.usd(1250));
      expect(s.usd.net, const Money.usd(18750));
    });

    test('negative net', () {
      final s = run([_tx(TransactionKind.expense, 1000)]);
      expect(s.tnd.net, const Money.tnd(-1000));
    });

    test('transfers and exchanges are not spending or income', () {
      final s = run([
        _tx(TransactionKind.transferOut, 50000),
        _tx(TransactionKind.transferIn, 50000, account: 'b'),
        _tx(TransactionKind.exchange, -100000, fee: 500),
        _tx(TransactionKind.exchange, 30000, currency: Currency.usd),
        _tx(TransactionKind.expense, 700),
      ]);
      expect(s.tnd.incomeMinor, 0);
      expect(s.tnd.spendingMinor, 700);
      expect(s.usd.isEmpty, isTrue);
    });

    test(
      'accounts excluded from totals, and unknown accounts, are skipped',
      () {
        final s = run([
          _tx(TransactionKind.income, 900, account: 'hidden'),
          _tx(TransactionKind.expense, 800, account: 'hidden'),
          _tx(TransactionKind.expense, 700, account: 'ghost'),
          _tx(TransactionKind.expense, 100),
        ]);
        expect(s.tnd.incomeMinor, 0);
        expect(s.tnd.spendingMinor, 100);
      },
    );

    test('only transactions inside the period count (edges included)', () {
      final s = run([
        _tx(TransactionKind.expense, 1, at: DateTime(2026, 9, 30, 23, 59, 59)),
        _tx(TransactionKind.expense, 10, at: DateTime(2026, 10, 1)),
        _tx(TransactionKind.expense, 100, at: DateTime(2026, 10, 31, 23, 59)),
        _tx(TransactionKind.expense, 1000, at: DateTime(2026, 11, 1)),
        _tx(TransactionKind.expense, 10000, at: DateTime.utc(2026, 10, 20)),
      ]);
      expect(s.tnd.spendingMinor, 10110);
    });

    test('an expense fee counts as spending', () {
      final s = run([_tx(TransactionKind.expense, 1000, fee: 25)]);
      expect(s.tnd.spendingMinor, 1025);
    });

    test('categories are summed per currency, biggest first, null = none', () {
      final s = run([
        _tx(TransactionKind.expense, 100, category: 'food'),
        _tx(TransactionKind.expense, 300, category: 'bills'),
        _tx(TransactionKind.expense, 250, category: 'food'),
        _tx(TransactionKind.expense, 50),
        _tx(TransactionKind.expense, 99, currency: Currency.usd, category: 'x'),
      ]);
      expect(
        [for (final c in s.tnd.categories) c.categoryId],
        ['food', 'bills', null],
      );
      expect(s.tnd.categories.first.spendingMinor, 350);
      expect(s.usd.categories.single.categoryId, 'x');
    });

    test('all-in-TND converts USD with the rate and names it', () {
      final rate = RateEntry(
        id: 'r',
        date: DateTime(2026, 10, 10),
        tndPerUsdTenThousandths: 31250, // 3.1250
      );
      final s = run([
        _tx(TransactionKind.income, 1000),
        _tx(TransactionKind.expense, 500),
        _tx(TransactionKind.income, 1000, currency: Currency.usd), // $10.00
        _tx(TransactionKind.expense, 200, currency: Currency.usd), // $2.00
      ], rate: rate);
      final all = s.allInTnd!;
      expect(all.rateTenThousandths, 31250);
      expect(all.rateDate, DateTime(2026, 10, 10));
      expect(all.income, const Money.tnd(1000 + 31250));
      expect(all.spending, const Money.tnd(500 + 6250));
      expect(all.net, const Money.tnd(25500));
    });

    test('rate present but no USD activity still gives a total', () {
      final s = run(
        [_tx(TransactionKind.income, 900)],
        rate: RateEntry(
          id: 'r',
          date: DateTime(2026),
          tndPerUsdTenThousandths: 30000,
        ),
      );
      expect(s.allInTnd!.net, const Money.tnd(900));
    });
  });

  group('usdCentsToTndMillimes', () {
    test('exact and rounded half away from zero', () {
      expect(usdCentsToTndMillimes(100, 31250), 3125); // $1 = 3.125 TND
      expect(usdCentsToTndMillimes(1, 31250), 31); // 31.25 -> 31
      expect(usdCentsToTndMillimes(2, 31250), 63); // 62.5 -> 63
      expect(usdCentsToTndMillimes(-2, 31250), -63);
      expect(usdCentsToTndMillimes(0, 31250), 0);
    });
  });
}
