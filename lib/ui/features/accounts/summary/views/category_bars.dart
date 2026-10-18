import 'package:flutter/material.dart';

import '../../../../core/motion/daftar_motion.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';

/// One row of the breakdown.
class CategoryBarData {
  const CategoryBarData({
    required this.label,
    required this.amountText,
    required this.fraction,
  });

  final String label;

  /// Already formatted (or hidden).
  final String amountText;

  /// 0..1, share of the biggest row.
  final double fraction;
}

/// Horizontal bars, one per category, drawn by [BarPainter]. The bars grow in
/// with a standard ease; with "Remove animations" they appear at full length.
class CategoryBars extends StatelessWidget {
  const CategoryBars({super.key, required this.rows});

  final List<CategoryBarData> rows;

  /// Height of one bar.
  static const double barHeight = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final reduced = DaftarMotion.reduced(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Semantics(
              label: '${r.label}, ${r.amountText}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          r.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Flexible(
                        child: Text(
                          r.amountText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduced ? 1 : 0, end: 1),
                    duration: reduced ? Duration.zero : DaftarMotion.slow,
                    curve: DaftarMotion.standard,
                    builder: (context, grow, _) => CustomPaint(
                      size: const Size.fromHeight(barHeight),
                      painter: BarPainter(
                        fraction: r.fraction * grow,
                        fill: c.text.withValues(alpha: 0.7),
                        track: c.raised,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints a rounded track with a rounded fill of [fraction] (0..1) of its width.
class BarPainter extends CustomPainter {
  const BarPainter({
    required this.fraction,
    required this.fill,
    required this.track,
  });

  final double fraction;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    final f = fraction.clamp(0.0, 1.0);
    if (f <= 0) return;
    // Never narrower than a dot, so a tiny share is still visible.
    final w = (size.width * f).clamp(size.height, size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), radius),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(BarPainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}
