import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/data_providers.dart';
import '../../../../../domain/models/account.dart';
import '../../../../../domain/models/lookups.dart';
import '../../../../../domain/use_cases/period_summary.dart';
import '../../../../../domain/use_cases/summary_period.dart';

/// `settings` key of the hide-amounts eye.
const String summaryHideAmountsKey = 'hide_amounts';

/// The clock. Tests override it.
final summaryClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Whether amounts are shown as "••••".
///
/// Kept in one place on purpose: if the accounts feature ships its own
/// hide-amounts provider, make this provider watch that one instead (and drop
/// [SummaryHideAmounts.set]); nothing else in this folder needs to change.
final summaryHideAmountsProvider = NotifierProvider<SummaryHideAmounts, bool>(
  SummaryHideAmounts.new,
);

class SummaryHideAmounts extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final saved = await ref
          .read(settingsRepositoryProvider)
          .get(summaryHideAmountsKey);
      if (saved != null && ref.mounted) state = saved == 'true';
    } catch (_) {
      // No database (bare widget test): amounts stay visible.
    }
  }

  Future<void> set(bool hidden) async {
    state = hidden;
    try {
      await ref
          .read(settingsRepositoryProvider)
          .set(summaryHideAmountsKey, '$hidden');
    } catch (_) {
      // Not saved; the choice still holds for this session.
    }
  }
}

/// The period the Summary screen is showing.
final summaryPeriodProvider =
    NotifierProvider<SummaryPeriodController, SummaryPeriod>(
      SummaryPeriodController.new,
    );

class SummaryPeriodController extends Notifier<SummaryPeriod> {
  @override
  SummaryPeriod build() => SummaryPeriod.containing(
    SummaryGranularity.month,
    ref.read(summaryClockProvider)(),
  );

  DateTime get _now => ref.read(summaryClockProvider)();

  /// Switches granularity, staying on the period that is current when the
  /// shown one is the current one, else around the shown period's start.
  void setGranularity(SummaryGranularity g) {
    state = state.isCurrentOrFuture(_now)
        ? SummaryPeriod.containing(g, _now)
        : state.withGranularity(g);
  }

  bool get canGoNext => !state.isCurrentOrFuture(_now);

  void previous() => state = state.previous;

  void next() {
    if (canGoNext) state = state.next;
  }
}

final _accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).watchAll(),
);

final _latestRateProvider = StreamProvider<RateEntry?>(
  (ref) => ref.watch(rateEntriesRepositoryProvider).watchLatest(),
);

final _periodTransactionsProvider =
    StreamProvider.family<List<AccountTransaction>, SummaryPeriod>(
      (ref, period) => ref
          .watch(transactionsRepositoryProvider)
          .watchAll(from: period.start, to: period.end),
    );

/// The summary of [period], recomputed whenever accounts, transactions or the
/// latest rate change.
final periodSummaryProvider =
    Provider.family<AsyncValue<PeriodSummary>, SummaryPeriod>((ref, period) {
      final accounts = ref.watch(_accountsProvider);
      final txs = ref.watch(_periodTransactionsProvider(period));
      final rate = ref.watch(_latestRateProvider);
      final error = accounts.error ?? txs.error ?? rate.error;
      if (error != null) {
        return AsyncValue.error(error, StackTrace.current);
      }
      if (!accounts.hasValue || !txs.hasValue || !rate.hasValue) {
        return const AsyncValue.loading();
      }
      return AsyncValue.data(
        summarizePeriod(
          period: period,
          transactions: txs.requireValue,
          accounts: accounts.requireValue,
          rate: rate.requireValue,
        ),
      );
    });

/// Category rows by id (for the names in the breakdown).
final summaryCategoriesProvider = StreamProvider<Map<String, Category>>(
  (ref) => ref
      .watch(categoriesRepositoryProvider)
      .watchAll()
      .map((list) => {for (final c in list) c.id: c}),
);

/// This calendar month, for the Home card.
final currentMonthSummaryProvider = Provider<AsyncValue<PeriodSummary>>((ref) {
  final month = SummaryPeriod.containing(
    SummaryGranularity.month,
    ref.read(summaryClockProvider)(),
  );
  return ref.watch(periodSummaryProvider(month));
});
