import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../products/view_models/catalog_providers.dart';
import '../view_models/saved_lists_pricing.dart';

/// A thin progress bar that eases to its value (jumps with reduced motion).
class SavedListProgressBar extends StatelessWidget {
  const SavedListProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduced = DaftarMotion.reduced(context);
    return ClipRRect(
      borderRadius: Radii.pillR,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: reduced ? Duration.zero : DaftarMotion.base,
        curve: DaftarMotion.standard,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: Space.sm,
          backgroundColor: c.raised,
          color: c.text,
        ),
      ),
    );
  }
}

/// "x of y done" for a list.
String progressText(int checked, int count) {
  if (count == 0) return 'No items yet';
  if (checked == count) return 'All $count done';
  return '$checked of $count done';
}

/// The best store and total of a list, or why there is none.
class SavedListPriceLine extends ConsumerWidget {
  const SavedListPriceLine({super.key, required this.summary});

  final SavedListSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final total = summary.total;
    if (summary.itemCount == 0) return const SizedBox.shrink();
    if (total == null) {
      return Text(
        'No prices yet for these items',
        style: t.bodySmall?.copyWith(color: c.muted),
      );
    }
    final place = ref.watch(
      placesByIdProvider.select((m) => m[summary.bestPlaceId]?.name),
    );
    final missing = summary.unpricedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          place == null ? 'Best store' : 'Best store · $place',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.bodySmall?.copyWith(color: c.muted),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  total.format(),
                  maxLines: 1,
                  style: DaftarType.price(22, c.text),
                ),
              ),
            ),
            const SizedBox(width: Space.xs),
            Text(
              total.currency.code,
              style: DaftarType.price(12, c.muted).copyWith(letterSpacing: 0),
            ),
          ],
        ),
        if (missing > 0)
          Text(
            missing == 1
                ? '1 item has no price'
                : '$missing items have no price',
            style: t.bodySmall?.copyWith(color: c.amber),
          ),
      ],
    );
  }
}
