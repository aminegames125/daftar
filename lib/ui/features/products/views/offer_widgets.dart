import 'package:flutter/material.dart';

import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/relative_time.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../view_models/offer_rows.dart';
import 'price_widgets.dart';

/// A big price that counts up from zero when it appears.
/// With "Remove animations" on it shows the final number straight away.
class CountUpPrice extends StatelessWidget {
  const CountUpPrice({
    super.key,
    required this.amount,
    this.amountMax,
    this.size = 34,
  });

  final Money amount;
  final Money? amountMax;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (DaftarMotion.reduced(context)) {
      return PriceAmount(amount: amount, amountMax: amountMax, size: size);
    }
    return TweenAnimationBuilder<int>(
      key: ValueKey((amount, amountMax)),
      tween: IntTween(begin: 0, end: amount.minor),
      duration: DaftarMotion.slow * 2,
      curve: DaftarMotion.standard,
      builder: (context, minor, _) => PriceAmount(
        amount: Money(minor, amount.currency),
        // A range counts its minimum up and then shows the full range.
        amountMax: minor == amount.minor ? amountMax : null,
        size: size,
      ),
    );
  }
}

/// The "Best option" card (lime chip, big price, "why it won" reasons). Shared by
/// the product page and Search.
class BestOptionCard extends StatelessWidget {
  const BestOptionCard({
    super.key,
    required this.title,
    required this.store,
    required this.amount,
    this.amountMax,
    required this.reasons,
    this.caption,
    this.unitLabel,
    this.onTap,
  });

  final String title;
  final String store;
  final Money amount;
  final Money? amountMax;
  final List<String> reasons;

  /// Right of the chip: "4 offers · 3 variants".
  final String? caption;

  /// "2.500 TND / 100 g" under the price when offers were compared by unit.
  final String? unitLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Squish(
      onTap: onTap,
      enabled: onTap != null,
      child: Semantics(
        container: true,
        label:
            'Best option: $title at $store, ${amount.formatWithCode()}. ${reasons.join(', ')}',
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
                  children: [
                    const BestOptionChip(),
                    const Spacer(),
                    if (caption != null)
                      Flexible(
                        child: Text(
                          caption!,
                          style: t.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: t.headlineSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            store,
                            style: t.bodySmall?.copyWith(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    CountUpPrice(amount: amount, amountMax: amountMax),
                  ],
                ),
                if (unitLabel != null) ...[
                  const SizedBox(height: Space.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      unitLabel!,
                      style: t.bodySmall?.copyWith(
                        fontFeatures: DaftarType.tabular,
                      ),
                    ),
                  ),
                ],
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [for (final r in reasons) ReasonChip(r)],
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

/// One offer in a list: store, "3.4 km · 2 weeks ago", price and change label.
/// Stale offers fade to 40% and say "old".
class OfferTile extends StatelessWidget {
  const OfferTile({
    super.key,
    required this.row,
    required this.now,
    this.subtitlePrefix,
    this.onTap,
  });

  final OfferRow row;
  final DateTime now;

  /// Extra leading text (a variant name or option, "Oreo · 100 g").
  final String? subtitlePrefix;
  final VoidCallback? onTap;

  String get _meta {
    final entry = row.entry;
    final parts = [
      ?subtitlePrefix,
      if (row.distanceKm != null) formatKm(row.distanceKm!),
      relativeAge(entry.seenAt, now),
      if (row.isStale) 'old',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final entry = row.entry;
    final promo = entry.isPromo;
    return StaleFade(
      isStale: row.isStale,
      child: Semantics(
        button: onTap != null,
        label:
            '${row.title}, ${entry.amount.formatWithCode()}, $_meta${promo ? ', promo' : ''}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.inputR,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.title,
                          style: t.titleMedium?.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _meta,
                          style: t.bodySmall?.copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (promo) ...[
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: c.amber),
                                borderRadius: Radii.chipR,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                child: Text(
                                  'promo',
                                  style: t.labelSmall?.copyWith(
                                    color: c.amber,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                          ],
                          PriceAmount(
                            amount: entry.amount,
                            amountMax: entry.amountMax,
                            size: 16,
                            showCode: false,
                          ),
                        ],
                      ),
                      if (row.change != null)
                        PriceChangeLabel(change: row.change!, now: now),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
