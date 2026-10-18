import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/accounts_routes.dart';
import '../../../../app/routes/rates_routes.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/money.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../prices/views/widgets/form_bits.dart';
import '../transfers/views/exchange_sheet.dart';
import '../transfers/views/transfer_sheet.dart';
import '../view_models/accounts_providers.dart';
import 'account_widgets.dart';

/// All accounts: totals per currency on top, then one row per account with its
/// balance, an include-in-totals switch and a drag handle to reorder.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(accountsOverviewProvider);
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AccountsHeader(
              title: 'Accounts',
              trailing: HideAmountsButton(),
            ),
            Expanded(
              child: overview.when(
                loading: () => const _Loading(),
                error: (_, _) => const Center(
                  child: EmptyState(message: 'Could not load your accounts.'),
                ),
                data: (o) => o.accounts.isEmpty
                    ? Center(
                        child: EmptyState(
                          message: 'No accounts yet. Add your first one.',
                          actionLabel: 'Add account',
                          onAction: () =>
                              context.push(AccountsRoutes.newAccount),
                        ),
                      )
                    : _AccountList(overview: o),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.add_card_outlined,
            label: 'Add transaction',
            onTap: () => context.push(AccountsRoutes.addTransaction()),
          ),
          ToolbarAction(
            icon: Icons.swap_horiz_rounded,
            label: 'Transfer',
            onTap: () => showTransferSheet(context),
          ),
          ToolbarAction(
            icon: Icons.currency_exchange_rounded,
            label: 'Exchange',
            onTap: () => showExchangeSheet(context),
          ),
          ToolbarAction(
            icon: Icons.show_chart_rounded,
            label: 'Rates',
            onTap: () => context.push(RatesRoutes.rates),
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Add account',
          onTap: () => context.push(AccountsRoutes.newAccount),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(Space.gutter),
    child: Column(
      children: [
        Skeleton(height: 96),
        SizedBox(height: Space.md),
        Skeleton(height: 96),
      ],
    ),
  );
}

class _AccountList extends ConsumerWidget {
  const _AccountList({required this.overview});

  final AccountsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = overview.accounts;
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Chrome.contentBottomPadding,
      ),
      header: _TotalsCard(totals: overview.totals),
      itemCount: accounts.length,
      onReorderItem: (oldIndex, newIndex) {
        final next = [...accounts];
        next.insert(newIndex, next.removeAt(oldIndex));
        ref.read(accountActionsProvider).reorder(next);
      },
      itemBuilder: (context, i) {
        final a = accounts[i];
        return Padding(
          key: ValueKey(a.id),
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: AccountRow(
            account: a,
            balance: overview.balanceOf(a),
            index: i,
            onTap: () => context.push(AccountsRoutes.detail(a.id)),
            onIncludeChanged: (v) =>
                ref.read(accountActionsProvider).toggleIncludeInTotals(a, v),
          ),
        );
      },
    );
  }
}

/// One total per currency; never mixed. Accounts left out of totals are not counted.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final Map<Currency, Money> totals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final entries = [
      for (final cur in Currency.values)
        if (totals[cur] != null) totals[cur]!,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total', style: t.bodySmall),
          const SizedBox(height: Space.xs),
          if (entries.isEmpty)
            Text('Nothing counted yet', style: t.bodyMedium)
          else
            for (final m in entries)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: AmountText(m, size: 32),
              ),
        ],
      ),
    );
  }
}

/// A row of the account list. Also used by pickers that want the same look.
class AccountRow extends StatelessWidget {
  const AccountRow({
    super.key,
    required this.account,
    required this.balance,
    required this.index,
    required this.onTap,
    required this.onIncludeChanged,
  });

  final Account account;
  final Money balance;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<bool> onIncludeChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Squish(
      onTap: onTap,
      pressedScale: 0.98,
      child: Semantics(
        button: true,
        label: '${account.name}, ${account.kind.label}',
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.xs,
            Space.md,
          ),
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
                  Icon(accountIcon(account), size: 22, color: c.muted),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium,
                        ),
                        Text(
                          '${account.kind.label} · ${account.currency.code}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Semantics(
                      label: 'Hold and drag to move ${account.name}',
                      child: SizedBox.square(
                        dimension: Chrome.minTouch,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: Space.md),
                child: AmountText(
                  balance,
                  size: 28,
                  forceHide: account.hideAmount,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Include in totals',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall,
                    ),
                  ),
                  DaftarSwitch(
                    value: account.includeInTotals,
                    onChanged: onIncludeChanged,
                    label: 'Include ${account.name} in totals',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
