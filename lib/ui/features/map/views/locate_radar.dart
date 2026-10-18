import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';

/// "I'm here" radar: a sweep and two pulsing rings around a dot
/// while the phone is finding its position. With reduced motion it is a still
/// frame: dot plus two rings.
class LocateRadar extends StatefulWidget {
  const LocateRadar({super.key, this.size = 160, this.active = true});

  final double size;

  /// false draws the still frame (found / not searching).
  final bool active;

  @override
  State<LocateRadar> createState() => _LocateRadarState();
}

class _LocateRadarState extends State<LocateRadar>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 2000);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LocateRadar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.active && !DaftarMotion.reduced(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: widget.active ? 'Finding your location' : 'Your location',
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _RadarPainter(
              t: _c.isAnimating ? _c.value : 0.35,
              animated: _c.isAnimating,
              color: c.lime,
              dot: c.text,
              outline: c.background,
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.t,
    required this.animated,
    required this.color,
    required this.dot,
    required this.outline,
  });

  final double t;
  final bool animated;
  final Color color;
  final Color dot;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;

    // Two pulse rings, half a period apart.
    for (final shift in const [0.0, 0.5]) {
      final p = (t + shift) % 1.0;
      final r = maxR * Curves.easeOut.transform(p);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - p) * 0.7),
      );
    }

    // Sweep: a fading wedge rotating around the dot.
    if (animated) {
      final angle = t * 2 * math.pi;
      final rect = Rect.fromCircle(center: center, radius: maxR);
      canvas.drawCircle(
        center,
        maxR,
        Paint()
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: math.pi * 2,
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.28)],
            stops: const [0.75, 1.0],
            transform: GradientRotation(angle),
          ).createShader(rect),
      );
    }

    canvas.drawCircle(center, 9, Paint()..color = outline);
    canvas.drawCircle(center, 7, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.t != t || old.animated != animated || old.color != color;
}
