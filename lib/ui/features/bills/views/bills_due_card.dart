import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/bill.dart';
import '../../../../domain/use_cases/bill_summary.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/bills_providers.dart';
import 'bill_widgets.dart';

/// Home card: the bills overdue or due in the next 7 days, with what they add up
/// to per currency. Tapping opens the bills list. Its height follows its content,
/// so place it in a box that can grow.
///
/// Watching [billReminderSyncProvider] here also reschedules the reminders each
/// time the app starts on Home.
class BillsDueCard extends ConsumerWidget {
  const BillsDueCard({super.key, this.maxRows = 3});

  /// Bills listed before "+ N more".
  final int maxRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(billReminderSyncProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final now = ref.watch(billsNowProvider);
    final all = ref.watch(billsProvider).value;
    final List<Bill> due = all == null ? const [] : billsDueWithin(all, now);
    final shown = due.take(maxRows).toList();
    final more = due.length - shown.length;
    void open() => context.push(Routes.bills);

    final String summary;
    if (all == null) {
      summary = 'Loading...';
    } else if (all.isEmpty) {
      summary = 'Add your first bill';
    } else if (due.isEmpty) {
      summary = 'Nothing due in the next 7 days';
    } else {
      summary = due.length == 1 ? '1 bill due' : '${due.length} bills due';
    }

    return Semantics(
      button: true,
      label: 'Bills, $summary',
      excludeSemantics: true,
      onTap: open,
      child: Squish(
        onTap: open,
        pressedScale: 0.98,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.cardR,
            border: Border.all(color: c.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long_outlined, color: c.muted),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        'Bills',
                        style: t.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(summary, style: t.bodySmall),
                if (shown.isNotEmpty) const SizedBox(height: Space.md),
                for (final b in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.name,
                                style: t.bodyMedium?.copyWith(color: c.text),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: null,
                              ),
                              Text(
                                dueLabel(b.nextDueAt, now),
                                style: t.bodySmall?.copyWith(
                                  color:
                                      billStatus(b, now) == BillStatus.overdue
                                      ? c.coral
                                      : c.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Flexible(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topRight,
                            child: AmountText(b.amount, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (more > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text('+ $more more', style: t.bodySmall),
                  ),
                if (due.length > 1) ...[
                  const SizedBox(height: Space.sm),
                  for (final money in sumByCurrency(due).values)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AmountText(money, size: 18),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
