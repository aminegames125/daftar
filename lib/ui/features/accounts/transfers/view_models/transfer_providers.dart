import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/data_providers.dart';
import '../../../../../data/repositories/rate_entries_repository.dart';
import '../../../../../data/repositories/transactions_repository.dart';
import '../../../../../domain/models/account.dart';
import '../../../../../domain/models/ids.dart';
import '../../../../../domain/models/money.dart';
import '../../../../../domain/use_cases/account_balance.dart';
import '../../../../../domain/use_cases/transfer_math.dart';

/// Live accounts for the transfer / exchange pickers.
final transferAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).watchAll(),
);

/// Current balance of one account (opening balance + its live transactions).
final transferBalanceProvider = StreamProvider.autoDispose
    .family<Money, String>((ref, accountId) {
      final accounts = ref.watch(transferAccountsProvider).value;
      final account = accounts?.where((a) => a.id == accountId).firstOrNull;
      if (account == null) return const Stream<Money>.empty();
      return ref
          .watch(transactionsRepositoryProvider)
          .watchForAccount(accountId)
          .map((txs) => accountBalance(account, txs));
    });

/// The newest saved USD/TND rate (null when none was ever saved).
final latestRateProvider = StreamProvider.autoDispose<RateEntry?>(
  (ref) => ref.watch(rateEntriesRepositoryProvider).watchLatest(),
);

/// Every exchange, both legs together, newest first.
final exchangeRecordsProvider =
    StreamProvider.autoDispose<List<ExchangeRecord>>(
      (ref) => ref
          .watch(transactionsRepositoryProvider)
          .watchAll()
          .map(groupExchanges),
    );

/// Writes for the transfer and exchange sheets and the exchange log.
class TransferActions {
  TransferActions(this._transactions, this._rates, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final TransactionsRepository _transactions;
  final RateEntriesRepository _rates;
  final DateTime Function() _now;

  /// The balance of [account] right now.
  Future<Money> balanceOf(Account account) async => accountBalance(
    account,
    await _transactions.watchForAccount(account.id).first,
  );

  /// Saves both legs atomically.
  Future<void> saveTransfer({
    required Account from,
    required Account to,
    required int amountMinor,
    int feeMinor = 0,
    String? note,
  }) => _transactions.saveAll(
    buildTransferLegs(
      from: from,
      to: to,
      amountMinor: amountMinor,
      feeMinor: feeMinor,
      at: _now(),
      note: note,
    ),
  );

  /// Saves both legs atomically, then records the rate when it differs from the
  /// latest saved one.
  Future<void> saveExchange({
    required Account from,
    required Account to,
    required int sendMinor,
    required int rateTenThousandths,
    int feeMinor = 0,
    String? note,
  }) async {
    final now = _now();
    await _transactions.saveAll(
      buildExchangeLegs(
        from: from,
        to: to,
        sendMinor: sendMinor,
        rateTenThousandths: rateTenThousandths,
        feeMinor: feeMinor,
        at: now,
        note: note,
      ),
    );
    final latest = await _rates.latest();
    if (latest == null ||
        latest.tndPerUsdTenThousandths != rateTenThousandths) {
      await _rates.save(
        RateEntry(
          id: newId(),
          date: now,
          tndPerUsdTenThousandths: rateTenThousandths,
          sourceNote: 'Exchange',
        ),
      );
    }
  }

  /// Soft-deletes both legs.
  Future<void> deleteExchange(String pairId) async {
    final legs = await _transactions.getByPairId(pairId);
    if (legs.isEmpty) return;
    await _transactions.delete(legs.first.id);
  }
}

final transferActionsProvider = Provider<TransferActions>(
  (ref) => TransferActions(
    ref.watch(transactionsRepositoryProvider),
    ref.watch(rateEntriesRepositoryProvider),
  ),
);
