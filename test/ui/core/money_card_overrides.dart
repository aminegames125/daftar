import 'package:daftar/domain/models/bill.dart';
import 'package:daftar/domain/use_cases/period_summary.dart';
import 'package:daftar/ui/features/accounts/summary/view_models/summary_providers.dart';
import 'package:daftar/ui/features/accounts/view_models/accounts_providers.dart';
import 'package:daftar/ui/features/bills/view_models/bills_providers.dart';
import 'package:daftar/ui/features/debts/view_models/debt_items.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Empty data for the Home money cards (accounts summary, bills due, debts), so
/// Home tests need no database and start no notification plugin.
final List<Override> moneyCardOverrides = [
  accountsOverviewProvider.overrideWithValue(
    const AsyncLoading<AccountsOverview>(),
  ),
  summaryHideAmountsProvider.overrideWith(_AmountsShown.new),
  billReminderSyncProvider.overrideWith((ref) {}),
  billsProvider.overrideWith((ref) => Stream.value(const <Bill>[])),
  debtTotalsProvider.overrideWithValue(const DebtTotals()),
  currentMonthSummaryProvider.overrideWithValue(
    const AsyncLoading<PeriodSummary>(),
  ),
];

/// "Hide amounts" off, without reading the settings table.
class _AmountsShown extends SummaryHideAmounts {
  @override
  bool build() => false;
}
