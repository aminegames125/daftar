import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// The "your usual" star. Turning it on pops the star and bursts a few sparks
/// around it. Reduced motion: it just switches.
class UsualStar extends StatefulWidget {
  const UsualStar({
    super.key,
    required this.isUsual,
    required this.onChanged,
    this.itemName,
  });

  final bool isUsual;
  final ValueChanged<bool> onChanged;

  /// For the screen reader ("Mark Capucin as your usual").
  final String? itemName;

  @override
  State<UsualStar> createState() => _UsualStarState();
}

class _UsualStarState extends State<UsualStar> with TickerProviderStateMixin {
  late final AnimationController _pop = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: DaftarMotion.slow,
    value: 1,
  );

  @override
  void didUpdateWidget(UsualStar old) {
    super.didUpdateWidget(old);
    if (!old.isUsual && widget.isUsual && !DaftarMotion.reduced(context)) {
      _pop.value = 0.5;
      _pop.animateWith(SpringSimulation(DaftarMotion.bouncy, 0.5, 1, 0));
      _burst.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = widget.itemName ?? 'this item';
    return Semantics(
      button: true,
      toggled: widget.isUsual,
      label: widget.isUsual
          ? 'Remove $name from your usual'
          : 'Mark $name as your usual',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onChanged(!widget.isUsual);
        },
        child: SizedBox.square(
          dimension: Chrome.minTouch,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pop, _burst]),
            builder: (context, _) => CustomPaint(
              foregroundPainter: _SparkPainter(
                t: _burst.value,
                color: c.accentText,
              ),
              child: Transform.scale(
                scale: _pop.value,
                child: Icon(
                  widget.isUsual
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: widget.isUsual ? c.accentText : c.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.t, required this.color});

  final double t;
  final Color color;

  static const _count = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final center = size.center(Offset.zero);
    final eased = Curves.easeOut.transform(t);
    for (var i = 0; i < _count; i++) {
      final angle = i * 2 * math.pi / _count - math.pi / 2;
      final radius = 10 + 12 * eased;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        2.5 * (1 - t),
        Paint()..color = color.withValues(alpha: 1 - t),
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t || old.color != color;
}
