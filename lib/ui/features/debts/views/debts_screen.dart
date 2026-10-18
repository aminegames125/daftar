import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/debts_routes.dart';
import '../../../../domain/models/debt.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../view_models/debt_actions.dart';
import '../view_models/debt_items.dart';
import 'debt_widgets.dart';
import 'repayment_progress.dart';

/// All debts, grouped by direction, with what is still open per currency.
class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(debtItemsProvider);
    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('Debts & loans')),
      bottomNavigationBar: DaftarActionBar(
        actions: const [],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Add debt',
          onTap: () => context.push(DebtsRoutes.add),
        ),
      ),
      body: items.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const Center(child: Text('Could not load debts.')),
        data: (list) => list.isEmpty
            ? Center(
                child: EmptyState(
                  message: 'No debts yet. Track money lent or borrowed.',
                  actionLabel: 'Add debt',
                  onAction: () => context.push(DebtsRoutes.add),
                ),
              )
            : _DebtList(items: list),
      ),
    );
  }
}

class _DebtList extends StatelessWidget {
  const _DebtList({required this.items});

  final List<DebtItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Chrome.contentBottomPadding,
      ),
      children: [
        for (final d in DebtDirection.values)
          _Group(
            direction: d,
            items: [
              for (final i in items)
                if (i.debt.direction == d) i,
            ],
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.direction, required this.items});

  final DebtDirection direction;
  final List<DebtItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    // Open ones first, settled ones last.
    final sorted = [
      ...items.where((i) => !i.settled),
      ...items.where((i) => i.settled),
    ];
    final open = totalsOf(items);
    final totals = moneyList(
      direction == DebtDirection.owedToMe ? open.owedToMe : open.owedByMe,
    );
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(direction.icon, size: 18, color: c.muted),
              const SizedBox(width: Space.sm),
              Expanded(child: Text(direction.label, style: t.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text('Still open', style: t.bodySmall),
          const SizedBox(height: Space.xs),
          MoneyLines(totals, size: 22),
          const SizedBox(height: Space.md),
          for (final i in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: DebtRow(item: i),
            ),
        ],
      ),
    );
  }
}

/// One debt in the list.
class DebtRow extends StatelessWidget {
  const DebtRow({super.key, required this.item});

  final DebtItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final d = item.debt;
    return Squish(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(DebtsRoutes.detail(d.id));
      },
      child: Semantics(
        button: true,
        label:
            '${d.name}, ${item.settled ? 'settled' : '${item.remaining.formatWithCode()} left'}',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.cardR,
            border: Border.all(color: c.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        d.name,
                        style: t.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: null,
                      ),
                    ),
                    if (item.overdue) ...[
                      const SizedBox(width: Space.sm),
                      const OverdueBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: Space.sm),
                if (item.settled)
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: c.accentText,
                      ),
                      const SizedBox(width: Space.xs),
                      Flexible(
                        child: Text(
                          'Settled · ${d.amount.formatWithCode()}',
                          style: t.bodyMedium?.copyWith(color: c.muted),
                        ),
                      ),
                    ],
                  )
                else ...[
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: Space.sm,
                    children: [
                      MoneyLine(item.remaining, size: 20),
                      Text('left of ${d.amount.format()}', style: t.bodySmall),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  RepaymentBar(progress: item.progress),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
