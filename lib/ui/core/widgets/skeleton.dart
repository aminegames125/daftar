import 'package:flutter/material.dart';

import '../motion/daftar_motion.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';

/// Motion skeleton shimmer: a placeholder block with a soft light sweep.
/// Use it where the layout is known but data is still loading (< 1 s, no spinner).
/// With "Remove animations" on it stays a still block.
///
/// ```dart
/// Skeleton(width: 120, height: 14)
/// ```
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = Radii.chip,
  });

  /// null = fill the available width.
  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  static const Duration _sweep = Duration(milliseconds: 1400);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _sweep,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = DaftarMotion.reduced(context);
    if (reduced && _c.isAnimating) _c.stop();
    if (!reduced && !_started) {
      _started = true;
      _c.repeat();
    }
    if (reduced) _started = false;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shine = Color.lerp(c.raised, c.text, 0.07)!;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final x = -1.5 + 3 * _c.value;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: _c.isAnimating
                  ? LinearGradient(
                      begin: Alignment(x - 1, 0),
                      end: Alignment(x + 1, 0),
                      colors: [c.raised, shine, c.raised],
                    )
                  : null,
              color: _c.isAnimating ? null : c.raised,
            ),
          );
        },
      ),
    );
  }
}

/// A list of skeleton rows (icon tile + two lines + trailing value) matching the
/// standard list row (56–58 px). Pass it as the `loading` state of lists.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < itemCount; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.sm),
              child: Row(
                children: [
                  Skeleton(width: 40, height: 40, radius: Radii.input - 2),
                  SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 140, height: 14),
                        SizedBox(height: Space.sm),
                        Skeleton(width: 96, height: 12),
                      ],
                    ),
                  ),
                  SizedBox(width: Space.md),
                  Skeleton(width: 48, height: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
