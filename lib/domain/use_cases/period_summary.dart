import '../models/account.dart';
import '../models/money.dart';
import 'summary_period.dart';

/// Spending of one category inside a period (one currency).
class CategorySpend {
  const CategorySpend(this.categoryId, this.spendingMinor);

  /// null = uncategorised.
  final String? categoryId;
  final int spendingMinor;
}

/// Income / spending of one currency inside a period.
class CurrencySummary {
  const CurrencySummary({
    required this.currency,
    this.incomeMinor = 0,
    this.spendingMinor = 0,
    this.categories = const [],
  });

  final Currency currency;
  final int incomeMinor;
  final int spendingMinor;

  /// Spending per category, biggest first.
  final List<CategorySpend> categories;

  int get netMinor => incomeMinor - spendingMinor;
  bool get isEmpty => incomeMinor == 0 && spendingMinor == 0;

  Money get income => Money(incomeMinor, currency);
  Money get spending => Money(spendingMinor, currency);
  Money get net => Money(netMinor, currency);
}

/// Everything, USD folded into TND with one rate.
class TndEquivalent {
  const TndEquivalent({
    required this.income,
    required this.spending,
    required this.rateTenThousandths,
    required this.rateDate,
  });

  final Money income;
  final Money spending;
  final int rateTenThousandths;
  final DateTime rateDate;

  Money get net => income - spending;
}

/// The summary of one [SummaryPeriod].
class PeriodSummary {
  const PeriodSummary({
    required this.period,
    required this.tnd,
    required this.usd,
    this.allInTnd,
  });

  final SummaryPeriod period;
  final CurrencySummary tnd;
  final CurrencySummary usd;

  /// null when there is no exchange rate yet.
  final TndEquivalent? allInTnd;

  CurrencySummary of(Currency c) => c == Currency.tnd ? tnd : usd;
  bool get isEmpty => tnd.isEmpty && usd.isEmpty;
}

/// Converts USD cents to TND millimes, rounding half away from zero.
/// rate = TND per 1 USD x 10 000, so millimes = cents x 10 x rate / 10 000.
int usdCentsToTndMillimes(int cents, int rateTenThousandths) {
  final numerator = cents * rateTenThousandths;
  const den = 1000;
  final q = (numerator.abs() + den ~/ 2) ~/ den;
  return numerator < 0 ? -q : q;
}

/// Builds the summary of [period].
///
/// - Only accounts with `includeInTotals` count (unknown / deleted accounts are
///   skipped too).
/// - Only `expense` and `income` count. Transfers and exchanges just move money
///   between accounts and are ignored, their fees included.
/// - An expense's fee counts as spending (it left the account).
/// - Instants are compared as absolute times against the period's local bounds.
PeriodSummary summarizePeriod({
  required SummaryPeriod period,
  required Iterable<AccountTransaction> transactions,
  required Iterable<Account> accounts,
  RateEntry? rate,
}) {
  final counted = {
    for (final a in accounts)
      if (a.includeInTotals) a.id,
  };
  final income = {Currency.tnd: 0, Currency.usd: 0};
  final spending = {Currency.tnd: 0, Currency.usd: 0};
  final byCategory = {
    Currency.tnd: <String?, int>{},
    Currency.usd: <String?, int>{},
  };

  for (final t in transactions) {
    if (!counted.contains(t.accountId) || !period.contains(t.occurredAt)) {
      continue;
    }
    switch (t.kind) {
      case TransactionKind.income:
        income[t.currency] = income[t.currency]! + t.amountMinor;
      case TransactionKind.expense:
        final out = t.amountMinor + (t.feeMinor ?? 0);
        spending[t.currency] = spending[t.currency]! + out;
        final cats = byCategory[t.currency]!;
        cats[t.categoryId] = (cats[t.categoryId] ?? 0) + out;
      case TransactionKind.transferOut:
      case TransactionKind.transferIn:
      case TransactionKind.exchange:
        break;
    }
  }

  CurrencySummary build(Currency c) {
    final cats = [
      for (final e in byCategory[c]!.entries)
        if (e.value > 0) CategorySpend(e.key, e.value),
    ]..sort((a, b) => b.spendingMinor.compareTo(a.spendingMinor));
    return CurrencySummary(
      currency: c,
      incomeMinor: income[c]!,
      spendingMinor: spending[c]!,
      categories: cats,
    );
  }

  final tnd = build(Currency.tnd);
  final usd = build(Currency.usd);

  TndEquivalent? all;
  if (rate != null) {
    final r = rate.tndPerUsdTenThousandths;
    all = TndEquivalent(
      income: Money.tnd(
        tnd.incomeMinor + usdCentsToTndMillimes(usd.incomeMinor, r),
      ),
      spending: Money.tnd(
        tnd.spendingMinor + usdCentsToTndMillimes(usd.spendingMinor, r),
      ),
      rateTenThousandths: r,
      rateDate: rate.date,
    );
  }
  return PeriodSummary(period: period, tnd: tnd, usd: usd, allInTnd: all);
}
