import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/bill.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/bill_summary.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../view_models/bills_providers.dart';
import 'bill_widgets.dart';

/// All bills and subscriptions, soonest due first (`Routes.bills`).
class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(billReminderSyncProvider);
    final bills = ref.watch(billsProvider);
    final now = ref.watch(billsNowProvider);
    final count = bills.value?.length;

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: DaftarActionBar(
        actions: const [],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Add bill',
          onTap: () => context.push(Routes.billNew),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: 'Bills',
            subtitle: count == null
                ? null
                : (count == 1 ? '1 bill' : '$count bills'),
            expandedHeight: 120,
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: () =>
                  context.canPop() ? context.pop() : context.go(Routes.home),
            ),
          ),
          bills.when(
            loading: () => const SliverToBoxAdapter(
              child: SkeletonList(
                padding: EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                  vertical: Space.lg,
                ),
              ),
            ),
            error: (_, _) => const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(message: "Couldn't load your bills."),
            ),
            data: (list) {
              if (list.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyState(
                      message: 'No bills yet. Add STEG, SONEDE, Netflix...',
                      actionLabel: 'Add bill',
                      onAction: () => context.push(Routes.billNew),
                    ),
                  ),
                );
              }
              // Active bills by due date, then the paused ones.
              final sorted = [
                ...list.where((b) => b.isActive),
                ...list.where((b) => !b.isActive),
              ];
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Chrome.contentBottomPadding,
                ),
                sliver: SliverList.list(
                  children: [
                    MonthlyTotalsCard(totals: monthlyTotals(list)),
                    const SizedBox(height: Space.md),
                    for (final b in sorted)
                      BillRow(
                        key: ValueKey(b.id),
                        bill: b,
                        now: now,
                        onTap: () => context.push(Routes.billDetail(b.id)),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "About X per month", one line per currency (TND and USD are never added up).
class MonthlyTotalsCard extends StatelessWidget {
  const MonthlyTotalsCard({super.key, required this.totals});

  final Map<Currency, Money> totals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Per month', style: t.bodySmall),
            const SizedBox(height: Space.sm),
            if (totals.isEmpty)
              Text('Nothing active', style: t.titleMedium)
            else
              for (final money in totals.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AmountText(money, size: 28),
                  ),
                ),
            const SizedBox(height: Space.xs),
            Text(
              'Yearly, weekly and custom bills are averaged. Paused bills are left out.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Used by the detail screen too.
String monthlyEquivalent(Bill b) =>
    Money(monthlyMinor(b), b.currency).formatWithCode();
