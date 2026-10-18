import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/account_balance.dart';

/// `settings` keys owned by the accounts feature.
abstract final class AccountSettingKeys {
  /// 'true' / 'false'. Masks every balance in the app.
  static const hideAmounts = 'hide_amounts';

  /// Id of the account used by the last saved transaction.
  static const lastAccountId = 'last_account_id';
}

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).watchAll(),
);

/// Transactions of every live account, newest first.
final allTransactionsProvider = StreamProvider<List<AccountTransaction>>(
  (ref) => ref.watch(transactionsRepositoryProvider).watchAll(),
);

final accountTransactionsProvider =
    StreamProvider.family<List<AccountTransaction>, String>(
      (ref, accountId) =>
          ref.watch(transactionsRepositoryProvider).watchForAccount(accountId),
    );

/// Balances per account and totals per currency. TND and USD are never added.
class AccountsOverview {
  const AccountsOverview({
    required this.accounts,
    required this.balances,
    required this.totals,
  });

  final List<Account> accounts;

  /// Account id -> balance in the account's own currency.
  final Map<String, Money> balances;

  /// Only accounts that are included in totals; a currency without accounts is absent.
  final Map<Currency, Money> totals;

  Money balanceOf(Account a) =>
      balances[a.id] ?? Money(a.openingBalanceMinor, a.currency);
}

AccountsOverview buildAccountsOverview(
  List<Account> accounts,
  List<AccountTransaction> transactions,
) {
  final byAccount = <String, List<AccountTransaction>>{};
  for (final t in transactions) {
    (byAccount[t.accountId] ??= []).add(t);
  }
  return AccountsOverview(
    accounts: accounts,
    balances: {
      for (final a in accounts)
        a.id: accountBalance(a, byAccount[a.id] ?? const []),
    },
    totals: totalsByCurrency(accounts, transactions),
  );
}

final accountsOverviewProvider = Provider<AsyncValue<AccountsOverview>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final transactions = ref.watch(allTransactionsProvider);
  if (accounts.hasError) {
    return AsyncError(accounts.error!, accounts.stackTrace ?? StackTrace.empty);
  }
  if (transactions.hasError) {
    return AsyncError(
      transactions.error!,
      transactions.stackTrace ?? StackTrace.empty,
    );
  }
  if (!accounts.hasValue || !transactions.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    buildAccountsOverview(accounts.requireValue, transactions.requireValue),
  );
});

/// One account by id (null while loading or when it does not exist).
final accountByIdProvider = Provider.family<Account?, String>((ref, id) {
  for (final a in ref.watch(accountsProvider).value ?? const <Account>[]) {
    if (a.id == id) return a;
  }
  return null;
});

/// Whether balances are masked everywhere. Saved in `settings`.
final hideAmountsProvider = NotifierProvider<HideAmounts, bool>(
  HideAmounts.new,
);

class HideAmounts extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final saved = await ref
          .read(settingsRepositoryProvider)
          .get(AccountSettingKeys.hideAmounts);
      if (saved != null && ref.mounted) state = saved == 'true';
    } catch (_) {
      // No database (bare widget test): keep amounts visible.
    }
  }

  Future<void> toggle() => set(!state);

  Future<void> set(bool hidden) {
    state = hidden;
    return ref
        .read(settingsRepositoryProvider)
        .set(AccountSettingKeys.hideAmounts, '$hidden');
  }
}

final accountActionsProvider = Provider<AccountActions>(AccountActions.new);

/// Writes of the accounts feature (views never touch repositories).
class AccountActions {
  AccountActions(this._ref);

  final Ref _ref;

  Future<Account?> getAccount(String id) =>
      _ref.read(accountsRepositoryProvider).getById(id);

  Future<AccountTransaction?> getTransaction(String id) =>
      _ref.read(transactionsRepositoryProvider).getById(id);

  Future<void> saveAccount(Account account) =>
      _ref.read(accountsRepositoryProvider).save(account);

  Future<void> deleteAccount(String id) =>
      _ref.read(accountsRepositoryProvider).delete(id);

  /// Rewrites the sort order after a drag; only changed rows are saved.
  Future<void> reorder(List<Account> ordered) async {
    final repo = _ref.read(accountsRepositoryProvider);
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) {
        await repo.save(ordered[i].copyWith(sortOrder: i));
      }
    }
  }

  Future<void> toggleIncludeInTotals(Account account, bool value) =>
      saveAccount(account.copyWith(includeInTotals: value));

  Future<void> saveTransaction(AccountTransaction transaction) async {
    await _ref.read(transactionsRepositoryProvider).save(transaction);
    await rememberAccount(transaction.accountId);
  }

  Future<void> deleteTransaction(String id) =>
      _ref.read(transactionsRepositoryProvider).delete(id);

  Future<void> rememberAccount(String accountId) async {
    try {
      await _ref
          .read(settingsRepositoryProvider)
          .set(AccountSettingKeys.lastAccountId, accountId);
    } catch (_) {
      // Remembering is a convenience only.
    }
  }

  /// The account of the last saved transaction, if it still exists; otherwise
  /// the first live account.
  Future<Account?> defaultAccount() async {
    final accounts = await _ref
        .read(accountsRepositoryProvider)
        .watchAll()
        .first;
    if (accounts.isEmpty) return null;
    String? last;
    try {
      last = await _ref
          .read(settingsRepositoryProvider)
          .get(AccountSettingKeys.lastAccountId);
    } catch (_) {
      last = null;
    }
    for (final a in accounts) {
      if (a.id == last) return a;
    }
    return accounts.first;
  }

  /// A new expense paying a logged price ("I bought it"). The transaction takes
  /// the account's currency; no conversion happens here.
  Future<AccountTransaction> recordPurchase({
    required Account account,
    required int amountMinor,
    required DateTime at,
    required String priceEntryId,
    String? note,
    String? categoryId,
  }) async {
    final tx = AccountTransaction(
      id: newId(),
      accountId: account.id,
      kind: TransactionKind.expense,
      amountMinor: amountMinor,
      currency: account.currency,
      occurredAt: at,
      categoryId: categoryId,
      note: note,
      priceEntryId: priceEntryId,
    );
    await saveTransaction(tx);
    return tx;
  }
}
