import '../models/account.dart';
import '../models/money.dart';

/// Balance = opening balance + every transaction's balance effect.
/// Transactions of other accounts are ignored.
Money accountBalance(
  Account account,
  Iterable<AccountTransaction> transactions,
) {
  var minor = account.openingBalanceMinor;
  for (final t in transactions) {
    if (t.accountId == account.id) minor += t.balanceEffectMinor;
  }
  return Money(minor, account.currency);
}

/// Sum of balances per currency over accounts flagged `includeInTotals`
/// (or all accounts when [onlyIncluded] is false). Currencies without accounts are absent.
Map<Currency, Money> totalsByCurrency(
  Iterable<Account> accounts,
  Iterable<AccountTransaction> transactions, {
  bool onlyIncluded = true,
}) {
  final byAccount = <String, List<AccountTransaction>>{};
  for (final t in transactions) {
    (byAccount[t.accountId] ??= []).add(t);
  }
  final totals = <Currency, Money>{};
  for (final a in accounts) {
    if (onlyIncluded && !a.includeInTotals) continue;
    final b = accountBalance(a, byAccount[a.id] ?? const []);
    totals[a.currency] = totals.containsKey(a.currency)
        ? totals[a.currency]! + b
        : b;
  }
  return totals;
}
