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
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/hold_to_confirm.dart';
import '../view_models/bills_providers.dart';
import 'bill_widgets.dart';
import 'bills_screen.dart' show monthlyEquivalent;

/// One bill: amount, schedule, payment history, and the actions
/// (`Routes.billDetail`).
class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({super.key, required this.billId});

  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(billReminderSyncProvider);
    final loaded = ref.watch(billsProvider).hasValue;
    final bill = ref.watch(billProvider(billId));
    final now = ref.watch(billsNowProvider);

    void back() => context.canPop() ? context.pop() : context.go(Routes.bills);
    final backButton = HeaderIconButton(
      icon: Icons.arrow_back_rounded,
      label: 'Back',
      onTap: back,
    );

    if (bill == null) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            CollapsingHeader(
              title: 'Bill',
              expandedHeight: 120,
              leading: backButton,
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: loaded
                  ? const EmptyState(message: 'This bill no longer exists.')
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }

    final actions = ref.read(billActionsProvider);
    final status = billStatus(bill, now);
    final paused = !bill.isActive;

    Future<void> markPaid() async {
      await actions.markPaid(bill.id);
      if (!context.mounted) return;
      final next = ref.read(billProvider(bill.id))?.nextDueAt;
      FloatingToast.show(
        context,
        'Paid ${bill.amount.formatWithCode()}',
        subtitle: next == null ? null : 'Next due ${shortDate(next)}',
        kind: ToastKind.success,
      );
    }

    Future<void> delete() async {
      final ok = await showHoldToConfirm(
        context,
        title: 'Delete ${bill.name}?',
        message: 'The bill and its payment history are removed from Daftar.',
        label: 'Hold to delete',
      );
      if (!ok) return;
      await actions.delete(bill.id);
      if (context.mounted) back();
    }

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            label: paused ? 'Resume bill' : 'Pause bill',
            onTap: () => actions.setActive(bill, paused),
          ),
          ToolbarAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete bill',
            onTap: delete,
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.check_rounded,
          label: 'Mark as paid',
          onTap: paused ? null : markPaid,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: bill.name,
            subtitle: cycleLabel(bill),
            expandedHeight: 120,
            leading: backButton,
            actions: [
              HeaderIconButton(
                icon: Icons.edit_outlined,
                label: 'Edit bill',
                onTap: () => context.push(Routes.billEdit(bill.id)),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              Chrome.contentBottomPadding,
            ),
            sliver: SliverList.list(
              children: [
                _SummaryCard(bill: bill, status: status, now: now),
                const SizedBox(height: Space.xxl),
                Text('Payments', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: Space.sm),
                _History(bill: bill),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.bill,
    required this.status,
    required this.now,
  });

  final Bill bill;
  final BillStatus status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final paused = status == BillStatus.paused;
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
            Row(
              children: [
                BillIconTile(bill.iconKey, dimmed: paused),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BillStatusChip(
                      status,
                      label: paused ? 'Paused' : dueLabel(bill.nextDueAt, now),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(bill.amount, size: 36),
            ),
            const SizedBox(height: Space.lg),
            _InfoLine(label: 'Next due', value: shortDate(bill.nextDueAt)),
            _InfoLine(label: 'Repeats', value: cycleLabel(bill)),
            _InfoLine(
              label: 'Reminder',
              value: switch (bill.reminderDaysBefore) {
                0 => 'On the day',
                1 => '1 day before',
                final n => '$n days before',
              },
            ),
            if (bill.cycle != BillCycle.monthly)
              _InfoLine(label: 'Per month', value: monthlyEquivalent(bill)),
            if (paused)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Paused bills have no reminders and are not counted.',
                  style: t.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: t.bodySmall)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(value, style: t.bodyMedium, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final payments = ref.watch(billPaymentsProvider(bill.id)).value;
    if (payments == null) return const SizedBox.shrink();
    if (payments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Text('No payments yet.', style: t.bodyMedium),
      );
    }
    return Column(
      children: [
        for (final p in payments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(shortDate(p.paidAt), style: t.bodyMedium)),
                const SizedBox(width: Space.md),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: AmountText(Money(p.amountMinor, bill.currency)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
