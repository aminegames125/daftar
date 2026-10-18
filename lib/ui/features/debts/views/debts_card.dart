import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/debts_routes.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/debt_items.dart';
import 'debt_widgets.dart';

/// Home card for Debts & loans: what others owe me and what I owe, per
/// currency. Opens the debts list (or [onTap]).
class DebtsCard extends ConsumerWidget {
  const DebtsCard({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final totals = ref.watch(debtTotalsProvider);
    return Squish(
      onTap: onTap ?? () => context.push(DebtsRoutes.list),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.cardR,
          border: Border.all(color: c.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.handshake_outlined, size: 20, color: c.muted),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text('Debts', style: t.titleMedium)),
                ],
              ),
              const SizedBox(height: Space.md),
              if (totals.isEmpty)
                Text('Nothing owed. All clear.', style: t.bodyMedium)
              else ...[
                Text('Owed to me', style: t.bodySmall),
                MoneyLines(moneyList(totals.owedToMe), size: 20),
                const SizedBox(height: Space.sm),
                Text('Owed by me', style: t.bodySmall),
                MoneyLines(moneyList(totals.owedByMe), size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
