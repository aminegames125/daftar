import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/debts_routes.dart';
import '../../../../domain/models/debt.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/hold_to_confirm.dart';
import '../../../core/widgets/success_check.dart';
import '../view_models/debt_actions.dart';
import '../view_models/debt_items.dart';
import 'add_payment_sheet.dart';
import 'debt_widgets.dart';
import 'repayment_progress.dart';

/// One debt: repayment ring, details and the payment history.
class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({super.key, required this.debtId});

  final String debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(debtItemProvider(debtId));
    final item = async.value;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            async.isLoading ? '' : 'This debt is gone.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(item.debt.name, overflow: TextOverflow.ellipsis),
      ),
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onTap: () => context.push(DebtsRoutes.edit(item.debt.id)),
          ),
          ToolbarAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            onTap: () => _deleteDebt(context, ref, item),
          ),
        ],
        primary: item.settled
            ? null
            : ToolbarAction(
                icon: Icons.add_rounded,
                label: 'Add payment',
                onTap: () => _addPayment(context, item),
              ),
      ),
      body: _Body(
        item: item,
        onDeletePayment: (p) => _deletePayment(context, ref, p),
      ),
    );
  }

  Future<void> _addPayment(BuildContext context, DebtItem item) async {
    final settled = await showAddPaymentSheet(context, item);
    if (settled == null || !context.mounted) return;
    FloatingToast.show(
      context,
      settled ? 'Settled' : 'Payment added',
      subtitle: settled ? item.debt.name : null,
      kind: ToastKind.success,
    );
  }

  Future<void> _deleteDebt(
    BuildContext context,
    WidgetRef ref,
    DebtItem item,
  ) async {
    final ok = await showHoldToConfirm(
      context,
      title: 'Delete this debt?',
      message: 'The debt and its payments will be removed.',
      label: 'Hold to delete',
    );
    if (!ok) return;
    await ref.read(debtActionsProvider).delete(item.debt.id);
    if (context.mounted) context.pop();
  }

  Future<void> _deletePayment(
    BuildContext context,
    WidgetRef ref,
    DebtPayment p,
  ) async {
    final ok = await showHoldToConfirm(
      context,
      title: 'Delete this payment?',
      message: 'The amount goes back to what is left.',
      label: 'Hold to delete',
    );
    if (ok) await ref.read(debtActionsProvider).deletePayment(p.id);
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.item, required this.onDeletePayment});

  final DebtItem item;
  final ValueChanged<DebtPayment> onDeletePayment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final d = item.debt;
    final loc = MaterialLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Chrome.contentBottomPadding,
      ),
      children: [
        Center(
          child: RepaymentRing(
            progress: item.progress,
            color: item.settled ? c.accentText : null,
            child: item.settled
                ? const SuccessCheck(size: 64)
                : Text(
                    '${(item.progress * 100).floor()}%',
                    style: t.headlineMedium,
                  ),
          ),
        ),
        const SizedBox(height: Space.lg),
        Center(
          child: item.settled
              ? Text('Settled', style: t.titleLarge)
              : MoneyLine(item.remaining, size: 32),
        ),
        const SizedBox(height: Space.xs),
        Center(
          child: Text(
            item.settled
                ? 'All ${d.amount.formatWithCode()} repaid'
                : 'left of ${d.amount.formatWithCode()}',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: Space.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              avatar: Icon(d.direction.icon, size: 16),
              label: Text(d.direction.label),
            ),
            if (item.overdue) const OverdueBadge(),
            if (d.dueAt != null)
              Chip(
                avatar: const Icon(Icons.event_outlined, size: 16),
                label: Text('Due ${loc.formatMediumDate(d.dueAt!.toLocal())}'),
              ),
          ],
        ),
        if (d.note != null && d.note!.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Text(d.note!, style: t.bodyMedium, textDirection: null),
        ],
        const SizedBox(height: Space.xxl),
        Text('Payments', style: t.titleMedium),
        const SizedBox(height: Space.sm),
        if (item.payments.isEmpty)
          Text('No payments yet.', style: t.bodySmall)
        else
          for (final p in item.payments)
            _PaymentTile(
              payment: p,
              currency: d.currency,
              date: loc.formatMediumDate(p.paidAt.toLocal()),
              onDelete: () => onDeletePayment(p),
            ),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.payment,
    required this.currency,
    required this.date,
    required this.onDelete,
  });

  final DebtPayment payment;
  final Currency currency;
  final String date;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final money = Money(payment.amountMinor, currency);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Chrome.minTouch),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.md,
              children: [
                MoneyLine(money, size: 18),
                Text(date, style: t.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete payment',
            constraints: const BoxConstraints.tightFor(
              width: Chrome.minTouch,
              height: Chrome.minTouch,
            ),
            icon: Icon(Icons.close_rounded, color: c.muted),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
