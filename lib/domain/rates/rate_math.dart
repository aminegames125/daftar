import '../models/account.dart';
import '../models/money.dart';

/// Pure USD/TND maths. A rate is TND per 1 USD times 10 000 (3.1250 -> 31250).
/// Everything is exact integer (BigInt inside) arithmetic, rounded half away
/// from zero, never `double`.
abstract final class RateMath {
  static const int scale = RateEntry.scale;

  static BigInt _div(BigInt n, BigInt d) {
    // Round half away from zero. [d] must be positive.
    final half = d ~/ BigInt.two;
    return n.isNegative ? -((-n + half) ~/ d) : (n + half) ~/ d;
  }

  /// TND for [usd] at [rate]. 100.00 USD at 3.1250 = 312.500 TND.
  static Money tndForUsd(Money usd, int rate) {
    _check(usd, Currency.usd, rate);
    // cents * rate/10000 * 1000/100 = cents * rate / 1000
    final v = _div(
      BigInt.from(usd.minor) * BigInt.from(rate),
      BigInt.from(1000),
    );
    return Money.tnd(v.toInt());
  }

  /// USD for [tnd] at [rate], rounded to the nearest cent.
  static Money usdForTnd(Money tnd, int rate) {
    _check(tnd, Currency.tnd, rate);
    final v = _div(
      BigInt.from(tnd.minor) * BigInt.from(1000),
      BigInt.from(rate),
    );
    return Money.usd(v.toInt());
  }

  /// USD to take from an account to cover [tnd] at [rate]: rounded UP to the
  /// next cent so the account never pays less than the price.
  static Money usdToCover(Money tnd, int rate) {
    _check(tnd, Currency.tnd, rate);
    if (tnd.minor <= 0) return usdForTnd(tnd, rate);
    final n = BigInt.from(tnd.minor) * BigInt.from(1000);
    final d = BigInt.from(rate);
    return Money.usd(((n + d - BigInt.one) ~/ d).toInt());
  }

  /// A fee as a percentage given in basis points (100 = 1%) of [amount].
  static Money feeFromBasisPoints(Money amount, int basisPoints) {
    if (basisPoints < 0) throw ArgumentError('negative fee');
    final v = _div(
      BigInt.from(amount.minor) * BigInt.from(basisPoints),
      BigInt.from(10000),
    );
    return Money(v.toInt(), amount.currency);
  }

  /// Effective rate (x10 000) of an exchange: (TND paid + TND fees) / USD received.
  /// Returns null when no USD was received.
  static int? effectiveRate({
    required Money tndPaid,
    Money? tndFees,
    required Money usdReceived,
  }) {
    if (tndPaid.currency != Currency.tnd ||
        usdReceived.currency != Currency.usd ||
        (tndFees != null && tndFees.currency != Currency.tnd)) {
      throw ArgumentError('tndPaid/fees must be TND and usdReceived USD');
    }
    if (usdReceived.minor <= 0) return null;
    final total = BigInt.from(tndPaid.minor) + BigInt.from(tndFees?.minor ?? 0);
    // tnd/1000 / (usd/100) * 10000 = tnd * 1000 / usd
    return _div(
      total * BigInt.from(1000),
      BigInt.from(usdReceived.minor),
    ).toInt();
  }

  /// Effective rate when paying a TND price from USD: the cost in USD (price
  /// converted at [rate] plus the USD [usdFee]) turned back into TND per USD.
  /// Equals [rate] when the fee is zero (up to one cent of rounding).
  static int? effectiveRateOfPayment({
    required Money tndPrice,
    required int rate,
    Money? usdFee,
  }) {
    final usd = usdToCover(tndPrice, rate);
    final total = Money.usd(usd.minor + (usdFee?.minor ?? 0));
    return effectiveRate(tndPaid: tndPrice, usdReceived: total);
  }

  /// Average rate weighted by USD amount. Null when [lots] has no positive amount.
  static int? weightedAverageRate(Iterable<RateLot> lots) {
    var weighted = BigInt.zero;
    var total = BigInt.zero;
    for (final l in lots) {
      if (l.usdCents <= 0) continue;
      weighted += BigInt.from(l.usdCents) * BigInt.from(l.rate);
      total += BigInt.from(l.usdCents);
    }
    if (total == BigInt.zero) return null;
    return _div(weighted, total).toInt();
  }

  /// Plain average of saved rates (history view, no amounts).
  static int? simpleAverageRate(Iterable<int> rates) {
    if (rates.isEmpty) return null;
    final sum = rates.fold(BigInt.zero, (a, r) => a + BigInt.from(r));
    return _div(sum, BigInt.from(rates.length)).toInt();
  }

  /// Gain or loss of holding [usdBalance] bought at [averageRate], valued at [currentRate].
  static GainLoss gainLoss({
    required Money usdBalance,
    required int averageRate,
    required int currentRate,
  }) {
    final cost = tndForUsd(usdBalance, averageRate);
    final value = tndForUsd(usdBalance, currentRate);
    final diff = value - cost;
    int? bp;
    if (cost.minor != 0) {
      bp = _div(
        BigInt.from(diff.minor) * BigInt.from(10000),
        BigInt.from(cost.minor.abs()),
      ).toInt();
    }
    return GainLoss(
      cost: cost,
      value: value,
      difference: diff,
      basisPoints: bp,
    );
  }

  // ---- text <-> rate ----

  /// "3.1250" for 31250. Always four decimals.
  static String formatRate(int rate) {
    final whole = rate.abs() ~/ scale;
    final frac = (rate.abs() % scale).toString().padLeft(4, '0');
    return '${rate < 0 ? '-' : ''}$whole.$frac';
  }

  /// "3.125", "3,1250", "3" to 31250. Null when invalid, zero or > 4 decimals.
  static int? tryParseRate(String input) {
    var t = input.trim().replaceAll(',', '.');
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    if (!RegExp(r'^\d{1,6}(\.\d{1,4})?$').hasMatch(t)) return null;
    final parts = t.split('.');
    final frac = (parts.length > 1 ? parts[1] : '').padRight(4, '0');
    final v = int.parse(parts[0]) * scale + int.parse(frac);
    return v > 0 ? v : null;
  }

  /// "+12.5%" / "-3.1%" / "0.0%" from basis points.
  static String formatPercent(int basisPoints) {
    final tenths = (basisPoints.abs() + 5) ~/ 10;
    final sign = tenths == 0 ? '' : (basisPoints > 0 ? '+' : '-');
    return '$sign${tenths ~/ 10}.${tenths % 10}%';
  }

  /// The USD lots an account was filled with: every exchange leg that brought
  /// USD in and carries a rate. Used for the average buy rate of an account.
  static List<RateLot> lotsFromTransactions(Iterable<AccountTransaction> txs) =>
      [
        for (final t in txs)
          if (t.kind == TransactionKind.exchange &&
              t.currency == Currency.usd &&
              t.amountMinor > 0 &&
              t.rateTenThousandths != null)
            RateLot(usdCents: t.amountMinor, rate: t.rateTenThousandths!),
      ];

  static void _check(Money m, Currency expected, int rate) {
    if (m.currency != expected) {
      throw ArgumentError('Expected ${expected.code}, got ${m.currency.code}');
    }
    if (rate <= 0) throw ArgumentError('rate must be positive');
  }
}

/// A batch of USD acquired at one rate (for the weighted average).
class RateLot {
  const RateLot({required this.usdCents, required this.rate});
  final int usdCents;
  final int rate;
}

/// Result of [RateMath.gainLoss].
class GainLoss {
  const GainLoss({
    required this.cost,
    required this.value,
    required this.difference,
    required this.basisPoints,
  });

  /// What the USD cost, in TND, at the average rate.
  final Money cost;

  /// What the USD is worth now, in TND.
  final Money value;

  /// value - cost; negative is a loss.
  final Money difference;

  /// difference / cost in basis points; null when cost is zero.
  final int? basisPoints;

  bool get isGain => difference.minor > 0;
  bool get isLoss => difference.minor < 0;
}
