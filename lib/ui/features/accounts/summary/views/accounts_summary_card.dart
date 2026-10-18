import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes/summary_routes.dart';
import '../../../../../domain/use_cases/period_summary.dart';
import '../../../../core/motion/squish.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';
import '../view_models/summary_providers.dart';
import 'summary_format.dart';

/// Compact Home card: this month's net per currency. Tapping opens the full
/// Summary screen (or calls [onTap]). It sizes itself to its content; the Home
/// stack gives it its slot.
class AccountsSummaryCard extends ConsumerWidget {
  const AccountsSummaryCard({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(currentMonthSummaryProvider).value;
    final hidden = ref.watch(summaryHideAmountsProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final open = onTap ?? () => context.push(SummaryRoutes.summary);

    return Semantics(
      button: true,
      label: 'Summary, this month',
      excludeSemantics: true,
      onTap: open,
      child: Squish(
        onTap: open,
        pressedScale: 0.98,
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.cardR,
            border: Border.all(color: c.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_outlined, size: 20, color: c.muted),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      'This month',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              if (summary == null)
                const SizedBox.shrink()
              else if (summary.isEmpty)
                Text('Nothing recorded yet', style: t.bodySmall)
              else
                for (final cs in [summary.tnd, summary.usd])
                  if (!cs.isEmpty) _NetLine(summary: cs, hidden: hidden),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetLine extends StatelessWidget {
  const _NetLine({required this.summary, required this.hidden});

  final CurrencySummary summary;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final negative = !hidden && summary.net.isNegative;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        children: [
          Text('Net', style: t.bodySmall),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              summaryMoney(summary.net, hidden: hidden, signed: true),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(
                color: negative ? c.coral : c.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
