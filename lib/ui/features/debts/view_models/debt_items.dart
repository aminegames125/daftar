import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/debt.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/debt_math.dart';

/// A debt with its payments and the numbers every screen needs.
class DebtItem {
  const DebtItem({
    required this.debt,
    required this.payments,
    required this.remaining,
    required this.overdue,
  });

  final Debt debt;

  /// Newest first.
  final List<DebtPayment> payments;
  final Money remaining;
  final bool overdue;

  bool get settled => remaining.minor == 0;

  Money get paid => Money(debt.amountMinor - remaining.minor, debt.currency);

  /// Repaid share, 0..1 (1 when the debt is settled, even if its amount is 0).
  double get progress {
    if (settled) return 1;
    return (debt.amountMinor - remaining.minor) / debt.amountMinor;
  }
}

/// Builds the [DebtItem]s from raw rows. Pure, so it is easy to test.
List<DebtItem> buildDebtItems(
  List<Debt> debts,
  List<DebtPayment> payments,
  DateTime now,
) {
  final byDebt = <String, List<DebtPayment>>{};
  for (final p in payments) {
    (byDebt[p.debtId] ??= []).add(p);
  }
  final today = DateTime(now.year, now.month, now.day);
  return [for (final d in debts) _item(d, byDebt[d.id] ?? const [], today)];
}

DebtItem _item(Debt d, List<DebtPayment> own, DateTime today) {
  final remaining = debtRemaining(d, own);
  final due = d.dueAt?.toLocal();
  return DebtItem(
    debt: d,
    payments: own,
    remaining: remaining,
    overdue:
        remaining.minor > 0 &&
        due != null &&
        DateTime(due.year, due.month, due.day).isBefore(today),
  );
}

/// Remaining (unpaid) amounts per currency; TND and USD are never added.
typedef CurrencyTotals = Map<Currency, int>;

/// Totals of unsettled debts, split by who owes whom.
class DebtTotals {
  const DebtTotals({this.owedToMe = const {}, this.owedByMe = const {}});

  /// Others owe me.
  final CurrencyTotals owedToMe;

  /// I owe others, plus what I borrowed from myself.
  final CurrencyTotals owedByMe;

  bool get isEmpty => owedToMe.isEmpty && owedByMe.isEmpty;
}

DebtTotals totalsOf(Iterable<DebtItem> items) {
  final toMe = <Currency, int>{};
  final byMe = <Currency, int>{};
  for (final i in items) {
    if (i.settled) continue;
    final target = i.debt.direction == DebtDirection.owedToMe ? toMe : byMe;
    target[i.debt.currency] =
        (target[i.debt.currency] ?? 0) + i.remaining.minor;
  }
  return DebtTotals(owedToMe: toMe, owedByMe: byMe);
}

/// Open amounts as money, TND first; empty when nothing is open.
List<Money> moneyList(CurrencyTotals totals) => [
  for (final c in Currency.values)
    if ((totals[c] ?? 0) > 0) Money(totals[c]!, c),
];

/// Clock, overridable in tests.
final debtsNowProvider = Provider<DateTime>((ref) => DateTime.now());

final _debtsProvider = StreamProvider<List<Debt>>(
  (ref) => ref.watch(debtsRepositoryProvider).watchAll(),
);

final _allPaymentsProvider = StreamProvider<List<DebtPayment>>(
  (ref) => ref.watch(debtsRepositoryProvider).watchAllPayments(),
);

/// All live debts with their numbers (loading until both streams delivered).
final debtItemsProvider = Provider<AsyncValue<List<DebtItem>>>((ref) {
  final debts = ref.watch(_debtsProvider);
  final payments = ref.watch(_allPaymentsProvider);
  final now = ref.watch(debtsNowProvider);
  if (debts.hasError) return AsyncError(debts.error!, debts.stackTrace!);
  if (payments.hasError) {
    return AsyncError(payments.error!, payments.stackTrace!);
  }
  final d = debts.value;
  final p = payments.value;
  if (d == null || p == null) return const AsyncLoading();
  return AsyncData(buildDebtItems(d, p, now));
});

/// One debt by id; null when it does not exist (or was deleted).
final debtItemProvider = Provider.family<AsyncValue<DebtItem?>, String>((
  ref,
  id,
) {
  return ref.watch(debtItemsProvider).whenData((items) {
    for (final i in items) {
      if (i.debt.id == id) return i;
    }
    return null;
  });
});

/// Totals for the Home card and the list header.
final debtTotalsProvider = Provider<DebtTotals>((ref) {
  final items = ref.watch(debtItemsProvider).value;
  return items == null ? const DebtTotals() : totalsOf(items);
});

/// Live accounts, for the "source account" choice.
final debtAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).watchAll(),
);
