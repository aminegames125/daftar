import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/accounts_routes.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/transaction_days.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../products/view_models/catalog_providers.dart';
import '../rates/usd_gain_loss_card.dart';
import '../view_models/accounts_providers.dart';
import 'account_widgets.dart';
import 'transaction_row.dart';

/// One account: its balance and its transactions grouped by day, newest first.
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final id = widget.accountId;
    // Closes itself when the account is deleted from its edit page.
    ref.listen(accountByIdProvider(id), (previous, next) {
      if (previous != null && next == null && context.canPop()) context.pop();
    });
    final account = ref.watch(accountByIdProvider(id));
    final accountsLoaded = ref.watch(accountsProvider).hasValue;
    final transactions = ref.watch(accountTransactionsProvider(id));
    final categories = {
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        c.id: c,
    };
    final now = ref.watch(clockProvider)();
    final overview = ref.watch(accountsOverviewProvider).value;

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AccountsHeader(
              title: account?.name ?? 'Account',
              trailing: const HideAmountsButton(),
            ),
            Expanded(
              child: account == null
                  ? Center(
                      child: accountsLoaded
                          ? const EmptyState(message: 'This account is gone.')
                          : const CircularProgressIndicator(),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.sm,
                        Space.gutter,
                        Chrome.contentBottomPadding,
                      ),
                      children: [
                        _BalanceCard(
                          account: account,
                          balance: overview?.balanceOf(account),
                        ),
                        // Shows itself only on USD accounts.
                        UsdGainLossCard(accountId: account.id),
                        const SizedBox(height: Space.lg),
                        ..._transactionSection(
                          context,
                          account,
                          transactions,
                          categories,
                          now,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.edit_outlined,
            label: 'Edit account',
            onTap: account == null
                ? null
                : () => context.push(AccountsRoutes.edit(id)),
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Add transaction',
          onTap: account == null
              ? null
              : () =>
                    context.push(AccountsRoutes.addTransaction(accountId: id)),
        ),
      ),
    );
  }

  List<Widget> _transactionSection(
    BuildContext context,
    Account account,
    AsyncValue<List<AccountTransaction>> transactions,
    Map<String, Category> categories,
    DateTime now,
  ) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final list = transactions.value;
    if (list == null) return const [SizedBox(height: Space.xxxl)];
    if (list.isEmpty) {
      return [
        const SizedBox(height: Space.xl),
        EmptyState(
          message: 'No transactions yet. Add an expense or income.',
          actionLabel: 'Add transaction',
          onAction: () => context.push(
            AccountsRoutes.addTransaction(accountId: account.id),
          ),
        ),
      ];
    }
    return [
      for (final day in groupTransactionsByDay(list)) ...[
        Padding(
          padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
          child: Text(
            dayHeading(day.day, now),
            style: t.labelLarge?.copyWith(color: c.muted),
          ),
        ),
        for (final tx in day.transactions)
          TransactionRow(
            transaction: tx,
            category: categories[tx.categoryId],
            onTap: tx.kind.isEditableHere
                ? () => context.push(AccountsRoutes.editTransaction(tx.id))
                : null,
          ),
      ],
    ];
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.account, required this.balance});

  final Account account;
  final Money? balance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(accountIcon(account), size: 20, color: c.muted),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  '${account.kind.label} · ${account.currency.code}'
                  '${account.includeInTotals ? '' : ' · not in totals'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (balance case final b?)
            AmountText(b, size: 40, forceHide: account.hideAmount),
        ],
      ),
    );
  }
}
