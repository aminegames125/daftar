import 'package:flutter/material.dart';

import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';

/// "120.000 TND": the number big, the code small and muted.
class MoneyLine extends StatelessWidget {
  const MoneyLine(this.money, {super.key, this.size = 20, this.color});

  final Money money;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: money.format(),
            style: DaftarType.price(size, color ?? c.text),
          ),
          TextSpan(
            text: ' ${money.currency.code}',
            style: DaftarType.price(
              size * 0.55,
              c.muted,
            ).copyWith(letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

/// Several amounts (one per currency) in a wrapping row; "None" when empty.
class MoneyLines extends StatelessWidget {
  const MoneyLines(this.amounts, {super.key, this.size = 20});

  final List<Money> amounts;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (amounts.isEmpty) {
      return Text('None', style: Theme.of(context).textTheme.bodyMedium);
    }
    return Wrap(
      spacing: Space.md,
      runSpacing: Space.xs,
      children: [for (final m in amounts) MoneyLine(m, size: size)],
    );
  }
}
