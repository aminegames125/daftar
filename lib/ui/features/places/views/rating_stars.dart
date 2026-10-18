import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// 1 to 5 stars: tapping a star fills the stars up to it, one by
/// one with a small pop. Tap the current rating again to clear it. With
/// [onChanged] null the stars are read-only.
class RatingStars extends StatefulWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.onChanged,
    this.size = 32,
  });

  final int? rating;
  final ValueChanged<int?>? onChanged;
  final double size;

  @override
  State<RatingStars> createState() => _RatingStarsState();
}

class _RatingStarsState extends State<RatingStars>
    with SingleTickerProviderStateMixin {
  static const _stagger = 0.12;
  late final AnimationController _pop = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  int _animateUpTo = 0;

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _tap(int star) {
    HapticFeedback.selectionClick();
    final next = widget.rating == star ? null : star;
    _animateUpTo = next ?? 0;
    if (next != null && !DaftarMotion.reduced(context)) {
      _pop.value = 0;
      _pop.animateWith(SpringSimulation(DaftarMotion.bouncy, 0, 1, 0));
    }
    widget.onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rating = widget.rating ?? 0;
    final interactive = widget.onChanged != null;
    final box = interactive ? Chrome.minTouch : widget.size;

    return Semantics(
      container: true,
      label: rating == 0 ? 'Not rated' : 'Rated $rating of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            AnimatedBuilder(
              animation: _pop,
              builder: (context, child) {
                // Stars up to the new rating pop in sequence.
                final delay = (star - 1) * _stagger;
                final t = star <= _animateUpTo
                    ? ((_pop.value - delay) / (1 - delay)).clamp(0.0, 1.4)
                    : 1.0;
                final scale = star <= _animateUpTo ? 0.6 + 0.4 * t : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: Semantics(
                button: interactive,
                label: interactive ? 'Rate $star' : null,
                excludeSemantics: interactive,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: interactive ? () => _tap(star) : null,
                  child: SizedBox.square(
                    dimension: box,
                    child: Icon(
                      star <= rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: widget.size,
                      color: star <= rating ? c.text : c.line,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
