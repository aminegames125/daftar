import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/rates/rate_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('conversion', () {
    test('tndForUsd is exact', () {
      expect(
        RateMath.tndForUsd(const Money.usd(10000), 31250),
        const Money.tnd(312500),
      );
      expect(
        RateMath.tndForUsd(const Money.usd(1), 31250),
        const Money.tnd(31),
      );
      expect(RateMath.tndForUsd(const Money.usd(0), 31250), const Money.tnd(0));
      expect(
        RateMath.tndForUsd(const Money.usd(-10000), 31250),
        const Money.tnd(-312500),
      );
    });
    test('usdForTnd rounds to nearest cent', () {
      expect(
        RateMath.usdForTnd(const Money.tnd(312500), 31250),
        const Money.usd(10000),
      );
      expect(
        RateMath.usdForTnd(const Money.tnd(500000), 31250),
        const Money.usd(16000),
      );
      expect(
        RateMath.usdForTnd(const Money.tnd(100000), 30000),
        const Money.usd(3333),
      );
      expect(
        RateMath.usdForTnd(const Money.tnd(200000), 30000),
        const Money.usd(6667),
      );
    });
    test('usdToCover rounds up', () {
      expect(
        RateMath.usdToCover(const Money.tnd(100000), 30000),
        const Money.usd(3334),
      );
      expect(
        RateMath.usdToCover(const Money.tnd(312500), 31250),
        const Money.usd(10000),
      );
    });
    test('large amounts stay exact', () {
      final r = RateMath.tndForUsd(const Money.usd(9000000000), 99990000);
      expect(r.minor, 9000000000 * 99990000 ~/ 1000);
    });
    test('wrong currency or rate throws', () {
      expect(
        () => RateMath.tndForUsd(const Money.tnd(1), 31250),
        throwsArgumentError,
      );
      expect(
        () => RateMath.usdForTnd(const Money.usd(1), 31250),
        throwsArgumentError,
      );
      expect(
        () => RateMath.tndForUsd(const Money.usd(1), 0),
        throwsArgumentError,
      );
    });
  });

  group('fees', () {
    test('basis points', () {
      expect(
        RateMath.feeFromBasisPoints(const Money.tnd(312500), 150),
        const Money.tnd(4688),
      );
      expect(
        RateMath.feeFromBasisPoints(const Money.usd(10000), 100),
        const Money.usd(100),
      );
      expect(
        RateMath.feeFromBasisPoints(const Money.usd(10000), 0),
        const Money.usd(0),
      );
      expect(
        () => RateMath.feeFromBasisPoints(const Money.usd(1), -1),
        throwsArgumentError,
      );
    });
  });

  group('effective rate', () {
    test('no fee equals the rate', () {
      expect(
        RateMath.effectiveRate(
          tndPaid: const Money.tnd(312500),
          usdReceived: const Money.usd(10000),
        ),
        31250,
      );
    });
    test('fees raise the cost of a buy', () {
      expect(
        RateMath.effectiveRate(
          tndPaid: const Money.tnd(312500),
          tndFees: const Money.tnd(5000),
          usdReceived: const Money.usd(10000),
        ),
        31750,
      );
    });
    test('rounds to the nearest ten-thousandth', () {
      expect(
        RateMath.effectiveRate(
          tndPaid: const Money.tnd(1000),
          usdReceived: const Money.usd(3),
        ),
        333333,
      );
    });
    test('no usd gives null', () {
      expect(
        RateMath.effectiveRate(
          tndPaid: const Money.tnd(1000),
          usdReceived: const Money.usd(0),
        ),
        isNull,
      );
    });
    test('wrong currencies throw', () {
      expect(
        () => RateMath.effectiveRate(
          tndPaid: const Money.usd(1),
          usdReceived: const Money.usd(1),
        ),
        throwsArgumentError,
      );
    });
    test('payment with a USD fee', () {
      // 312.500 TND at 3.1250 = 100.00 USD, plus 2.00 fee = 102.00 USD.
      expect(
        RateMath.effectiveRateOfPayment(
          tndPrice: const Money.tnd(312500),
          rate: 31250,
          usdFee: const Money.usd(200),
        ),
        30637,
      );
      expect(
        RateMath.effectiveRateOfPayment(
          tndPrice: const Money.tnd(312500),
          rate: 31250,
        ),
        31250,
      );
    });
  });

  group('averages', () {
    test('weighted by amount', () {
      final avg = RateMath.weightedAverageRate(const [
        RateLot(usdCents: 10000, rate: 30000),
        RateLot(usdCents: 30000, rate: 32000),
      ]);
      expect(avg, 31500);
    });
    test('ignores empty and non-positive lots', () {
      expect(RateMath.weightedAverageRate(const []), isNull);
      expect(
        RateMath.weightedAverageRate(const [RateLot(usdCents: 0, rate: 30000)]),
        isNull,
      );
      expect(
        RateMath.weightedAverageRate(const [
          RateLot(usdCents: -5, rate: 1),
          RateLot(usdCents: 100, rate: 30000),
        ]),
        30000,
      );
    });
    test('simple average', () {
      expect(RateMath.simpleAverageRate(const [30000, 31000, 32001]), 31000);
      expect(RateMath.simpleAverageRate(const []), isNull);
    });
    test('lots come from incoming USD exchange legs only', () {
      AccountTransaction tx(
        TransactionKind k,
        int amt,
        Currency c,
        int? rate,
      ) => AccountTransaction(
        id: '$k$amt$c',
        accountId: 'a',
        kind: k,
        amountMinor: amt,
        currency: c,
        occurredAt: DateTime(2026),
        rateTenThousandths: rate,
      );
      final lots = RateMath.lotsFromTransactions([
        tx(TransactionKind.exchange, 10000, Currency.usd, 31000),
        tx(TransactionKind.exchange, -5000, Currency.usd, 31000),
        tx(TransactionKind.exchange, 5000, Currency.tnd, 31000),
        tx(TransactionKind.exchange, 5000, Currency.usd, null),
        tx(TransactionKind.income, 5000, Currency.usd, 31000),
      ]);
      expect(lots.length, 1);
      expect(lots.single.usdCents, 10000);
    });
  });

  group('gain / loss', () {
    test('gain', () {
      final g = RateMath.gainLoss(
        usdBalance: const Money.usd(10000),
        averageRate: 30000,
        currentRate: 31500,
      );
      expect(g.cost, const Money.tnd(300000));
      expect(g.value, const Money.tnd(315000));
      expect(g.difference, const Money.tnd(15000));
      expect(g.basisPoints, 500);
      expect(g.isGain, isTrue);
      expect(g.isLoss, isFalse);
    });
    test('loss', () {
      final g = RateMath.gainLoss(
        usdBalance: const Money.usd(10000),
        averageRate: 32000,
        currentRate: 31000,
      );
      expect(g.difference, const Money.tnd(-10000));
      expect(g.basisPoints, -313);
      expect(g.isLoss, isTrue);
    });
    test('zero balance', () {
      final g = RateMath.gainLoss(
        usdBalance: const Money.usd(0),
        averageRate: 30000,
        currentRate: 31000,
      );
      expect(g.difference.minor, 0);
      expect(g.basisPoints, isNull);
    });
  });

  group('text', () {
    test('format and parse rate', () {
      expect(RateMath.formatRate(31250), '3.1250');
      expect(RateMath.formatRate(5), '0.0005');
      expect(RateMath.tryParseRate('3.125'), 31250);
      expect(RateMath.tryParseRate('3,1250'), 31250);
      expect(RateMath.tryParseRate('3.'), 30000);
      expect(RateMath.tryParseRate('3'), 30000);
      expect(RateMath.tryParseRate('3.12345'), isNull);
      expect(RateMath.tryParseRate('0'), isNull);
      expect(RateMath.tryParseRate(''), isNull);
      expect(RateMath.tryParseRate('abc'), isNull);
      expect(RateMath.tryParseRate('-3'), isNull);
    });
    test('format percent', () {
      expect(RateMath.formatPercent(500), '+5.0%');
      expect(RateMath.formatPercent(-313), '-3.1%');
      expect(RateMath.formatPercent(0), '0.0%');
      expect(RateMath.formatPercent(2), '0.0%');
      expect(RateMath.formatPercent(1250), '+12.5%');
    });
  });
}
