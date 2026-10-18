import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// Ring showing how much of a debt is repaid (0..1). The arc sweeps to its value
/// (jumps there with "Remove animations"). [child] sits in the middle.
class RepaymentRing extends StatelessWidget {
  const RepaymentRing({
    super.key,
    required this.progress,
    this.size = 148,
    this.strokeWidth = 12,
    this.color,
    this.child,
  });

  final double progress;
  final double size;
  final double strokeWidth;

  /// Arc colour; defaults to the text colour (lime is reserved for actions).
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduced = DaftarMotion.reduced(context);
    return Semantics(
      label: '${(progress * 100).floor()}% repaid',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0.0, 1.0)),
        duration: reduced ? Duration.zero : DaftarMotion.slow,
        curve: DaftarMotion.emphasized,
        builder: (context, value, child) => CustomPaint(
          size: Size.square(size),
          painter: RingPainter(
            progress: value,
            track: c.line,
            arc: color ?? c.text,
            strokeWidth: strokeWidth,
          ),
          child: SizedBox.square(dimension: size, child: child),
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  const RingPainter({
    required this.progress,
    required this.track,
    required this.arc,
    required this.strokeWidth,
  });

  final double progress;
  final Color track;
  final Color arc;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - strokeWidth) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        paint..color = arc,
      );
    }
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.arc != arc ||
      old.strokeWidth != strokeWidth;
}

/// Slim repayment bar for list rows.
class RepaymentBar extends StatelessWidget {
  const RepaymentBar({super.key, required this.progress, this.height = 6});

  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduced = DaftarMotion.reduced(context);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0.0, 1.0)),
        duration: reduced ? Duration.zero : DaftarMotion.base,
        curve: DaftarMotion.standard,
        builder: (context, value, _) => SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: BarPainter(progress: value, track: c.line, fill: c.text),
          ),
        ),
      ),
    );
  }
}

class BarPainter extends CustomPainter {
  const BarPainter({
    required this.progress,
    required this.track,
    required this.fill,
  });

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    final w = size.width * progress.clamp(0.0, 1.0);
    if (w > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, math.max(w, size.height), size.height),
          r,
        ),
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(BarPainter old) =>
      old.progress != progress || old.track != track || old.fill != fill;
}

/// Small "Overdue" pill (icon + word, never colour alone).
class OverdueBadge extends StatelessWidget {
  const OverdueBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.coral.withValues(alpha: 0.16),
        borderRadius: Radii.pillR,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 14, color: c.coral),
            const SizedBox(width: Space.xs),
            Text(
              'Overdue',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: c.coral),
            ),
          ],
        ),
      ),
    );
  }
}
