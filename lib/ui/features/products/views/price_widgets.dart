import 'package:flutter/material.dart';

import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/price_change.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';

/// "4.400" plus a small muted "TND", or "6.000–8.000" for a range.
class PriceAmount extends StatelessWidget {
  const PriceAmount({
    super.key,
    required this.amount,
    this.amountMax,
    this.size = 16,
    this.color,
    this.showCode = true,
    this.suffix,
  });

  final Money amount;
  final Money? amountMax;
  final double size;
  final Color? color;
  final bool showCode;

  /// Extra muted text after the code, e.g. "/ 100 g".
  final String? suffix;

  /// "6.000–8.000" or "4.400" (no currency code).
  String get text => amountMax == null
      ? amount.format()
      : '${amount.format()}–${amountMax!.format()}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label:
          '${amountMax == null ? amount.formatWithCode() : '$text ${amount.currency.code}'}${suffix == null ? '' : ' $suffix'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              text,
              style: DaftarType.price(size, color ?? c.text),
              maxLines: 1,
              overflow: TextOverflow.fade,
            ),
          ),
          if (showCode) ...[
            const SizedBox(width: Space.xs),
            Text(
              amount.currency.code,
              style: DaftarType.price(
                size * 0.4 < 11 ? 11 : size * 0.4,
                c.muted,
              ).copyWith(letterSpacing: 0),
            ),
          ],
          if (suffix != null) ...[
            const SizedBox(width: Space.xs),
            Text(
              suffix!,
              style: DaftarType.price(
                11,
                c.muted,
              ).copyWith(letterSpacing: 0, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

/// The lime "Best option" chip. Lime marks the one best answer on a screen.
class BestOptionChip extends StatelessWidget {
  const BestOptionChip({super.key, this.label = 'Best option'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.lime.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md - 2,
          vertical: Space.sm - 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: c.accentText, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// A small `raised` chip used for "why it won" reasons and other facts.
class ReasonChip extends StatelessWidget {
  const ReasonChip(this.label, {super.key, this.outlineColor});

  final String label;

  /// e.g. amber for a promo.
  final Color? outlineColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(10),
        border: outlineColor == null ? null : Border.all(color: outlineColor!),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md - 2,
          vertical: Space.sm - 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// "▲ +12% since March" in coral (price up) or "▼ -8% since March" in lime
/// (price down). Colour is never the only signal: the arrow and sign say it too.
/// A soft flash plays once when it appears.
class PriceChangeLabel extends StatelessWidget {
  const PriceChangeLabel({super.key, required this.change, required this.now});

  final PriceChange change;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = change.isUp ? c.coral : c.accentText;
    final tint = change.isUp ? c.coral : c.lime;
    final text = '${change.isUp ? '▲' : '▼'} ${change.label(now)}';
    final label = Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    );
    if (DaftarMotion.reduced(context)) return label;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.35, end: 0),
      duration: DaftarMotion.slow * 2,
      curve: DaftarMotion.standard,
      builder: (context, flash, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: flash * 0.5),
          borderRadius: Radii.chipR,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          child: child,
        ),
      ),
      child: label,
    );
  }
}

/// Fades a row to 40% when its price is stale (older than the threshold).
class StaleFade extends StatelessWidget {
  const StaleFade({super.key, required this.isStale, required this.child});

  final bool isStale;
  final Widget child;

  /// Stale = 40% opacity + "old".
  static const double staleOpacity = 0.4;

  @override
  Widget build(BuildContext context) =>
      isStale ? Opacity(opacity: staleOpacity, child: child) : child;
}
