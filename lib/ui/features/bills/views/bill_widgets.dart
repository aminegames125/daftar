import 'package:flutter/material.dart';

import '../../../../domain/models/bill.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/bill_summary.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';

/// A preset bill icon (STEG, SONEDE, ...). [key] is what the database stores.
class BillIconPreset {
  const BillIconPreset(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

const List<BillIconPreset> billIconPresets = [
  BillIconPreset('steg', 'STEG', Icons.bolt_rounded),
  BillIconPreset('sonede', 'SONEDE', Icons.water_drop_outlined),
  BillIconPreset('internet', 'Internet', Icons.wifi_rounded),
  BillIconPreset('topup', 'Mobile top-up', Icons.smartphone_rounded),
  BillIconPreset('rent', 'Rent', Icons.home_outlined),
  BillIconPreset('netflix', 'Netflix', Icons.play_circle_outline_rounded),
  BillIconPreset('receipt', 'Other', Icons.receipt_long_outlined),
];

IconData billIcon(String key) {
  for (final p in billIconPresets) {
    if (p.key == key) return p.icon;
  }
  return Icons.receipt_long_outlined;
}

String cycleLabel(Bill b) => switch (b.cycle) {
  BillCycle.monthly => 'Monthly',
  BillCycle.yearly => 'Yearly',
  BillCycle.weekly => 'Weekly',
  BillCycle.customDays =>
    b.customDays == 1 ? 'Every day' : 'Every ${b.customDays} days',
};

String statusText(BillStatus s) => switch (s) {
  BillStatus.overdue => 'Overdue',
  BillStatus.dueSoon => 'Due soon',
  BillStatus.later => 'Later',
  BillStatus.paused => 'Paused',
};

/// "12.500" in the text colour with a small muted currency code after it.
class AmountText extends StatelessWidget {
  const AmountText(this.money, {super.key, this.size = 16, this.color});

  final Money money;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: money.format()),
          TextSpan(
            text: ' ${money.currency.code}',
            style: DaftarType.price(size * 0.7, c.muted),
          ),
        ],
      ),
      style: DaftarType.price(size, color ?? c.text),
      textAlign: TextAlign.end,
    );
  }
}

/// Overdue (coral) / due soon (amber) / later and paused (muted) pill.
class BillStatusChip extends StatelessWidget {
  const BillStatusChip(this.status, {super.key, this.label});

  final BillStatus status;

  /// Defaults to [statusText].
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (status) {
      BillStatus.overdue => c.coral,
      BillStatus.dueSoon => c.amber,
      BillStatus.later || BillStatus.paused => c.muted,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: Radii.pillR,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs,
        ),
        child: Text(
          label ?? statusText(status),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// The round icon tile of a bill.
class BillIconTile extends StatelessWidget {
  const BillIconTile(this.iconKey, {super.key, this.dimmed = false});

  final String iconKey;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.raised, borderRadius: Radii.inputR),
      child: SizedBox.square(
        dimension: Chrome.minTouch,
        child: Icon(billIcon(iconKey), color: dimmed ? c.muted : c.text),
      ),
    );
  }
}

/// One line of the bills list.
class BillRow extends StatelessWidget {
  const BillRow({
    super.key,
    required this.bill,
    required this.now,
    required this.onTap,
  });

  final Bill bill;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final status = billStatus(bill, now);
    final paused = status == BillStatus.paused;
    return Semantics(
      button: true,
      label:
          '${bill.name}, ${bill.amount.formatWithCode()}, '
          '${paused ? 'paused' : dueLabel(bill.nextDueAt, now)}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: Radii.inputR,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Chrome.minTouch + 24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BillIconTile(bill.iconKey, dimmed: paused),
                const SizedBox(width: Space.md),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill.name,
                        style: t.titleMedium?.copyWith(
                          color: paused ? c.muted : c.text,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: null,
                      ),
                      const SizedBox(height: Space.xs),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          BillStatusChip(status),
                          Text(
                            paused
                                ? cycleLabel(bill)
                                : dueLabel(bill.nextDueAt, now),
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topRight,
                      child: AmountText(
                        bill.amount,
                        color: paused ? c.muted : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
