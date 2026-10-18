import 'package:go_router/go_router.dart';

import '../../domain/models/account.dart';
import '../../ui/features/accounts/views/account_detail_screen.dart';
import '../../ui/features/accounts/views/account_form_screen.dart';
import '../../ui/features/accounts/views/accounts_screen.dart';
import '../../ui/features/accounts/views/transaction_form_screen.dart';

/// Paths of the accounts feature. Other features (transfers, exchanges,
/// summaries) link to these with `context.push(...)`.
abstract final class AccountsRoutes {
  /// Account list: balances per currency, include-in-totals, reorder.
  static const list = '/accounts';
  static const newAccount = '/accounts/new';
  static String detail(String id) => '/accounts/$id';
  static String edit(String id) => '/accounts/$id/edit';

  /// New expense (default) or income. Pre-select the account with [accountId];
  /// without it the last used account is chosen.
  static String addTransaction({
    String? accountId,
    TransactionKind kind = TransactionKind.expense,
  }) => Uri(
    path: '/accounts/transactions/new',
    queryParameters: {'accountId': ?accountId, 'kind': kind.name},
  ).toString();

  /// Edit or delete an expense / income.
  static String editTransaction(String id) => '/accounts/transactions/$id';
}

/// Full-screen routes of the accounts feature.
///
/// Fixed paths come before `/accounts/:id` so "new" is not read as an id.
final List<RouteBase> accountsRoutes = [
  GoRoute(path: AccountsRoutes.list, builder: (_, _) => const AccountsScreen()),
  GoRoute(
    path: AccountsRoutes.newAccount,
    builder: (_, _) => const AccountFormScreen(),
  ),
  GoRoute(
    path: '/accounts/transactions/new',
    builder: (_, state) => TransactionFormScreen(
      accountId: state.uri.queryParameters['accountId'],
      initialKind:
          TransactionKind.values
              .asNameMap()[state.uri.queryParameters['kind']] ??
          TransactionKind.expense,
    ),
  ),
  GoRoute(
    path: '/accounts/transactions/:id',
    builder: (_, state) =>
        TransactionFormScreen(transactionId: state.pathParameters['id']),
  ),
  GoRoute(
    path: '/accounts/:id/edit',
    builder: (_, state) =>
        AccountFormScreen(accountId: state.pathParameters['id']),
  ),
  GoRoute(
    path: '/accounts/:id',
    builder: (_, state) =>
        AccountDetailScreen(accountId: state.pathParameters['id']!),
  ),
];
