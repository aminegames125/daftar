import 'package:flutter/material.dart';

import '../motion/daftar_motion.dart';
import '../theme/daftar_colors.dart';

/// The Daftar logo: the Arabic letter د (Dal) drawn as one stroke.
///
/// Geometry is fixed (120×120 design box, stroke 16, round caps/joins) and
/// must match assets/brand/dal_mark.svg exactly. [progress] draws the stroke
/// partially (0 = nothing, 1 = full), which powers every write-on animation.
class DalMark extends StatelessWidget {
  const DalMark({
    super.key,
    this.size = 48,
    this.color,
    this.progress = 1,
    this.strokeWidth = 16,
  });

  final double size;
  final Color? color;
  final double progress;

  /// Stroke width in the 120-unit design box (scaled with [size]).
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Daftar',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: DalPainter(
          color: color ?? context.colors.lime,
          progress: progress,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class DalPainter extends CustomPainter {
  DalPainter({required this.color, this.progress = 1, this.strokeWidth = 16});

  final Color color;
  final double progress;
  final double strokeWidth;

  /// Path in the 120×120 design box. Same as the SVG:
  /// M48 32 L74 66 C78 72 74 84 66 84 L42 84
  static Path designPath() => Path()
    ..moveTo(48, 32)
    ..lineTo(74, 66)
    ..cubicTo(78, 72, 74, 84, 66, 84)
    ..lineTo(42, 84);

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p == 0) return;
    final scale = size.shortestSide / 120;
    canvas.scale(scale);

    var path = designPath();
    if (p < 1) {
      final metric = path.computeMetrics().first;
      path = metric.extractPath(0, metric.length * p);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(DalPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.strokeWidth != strokeWidth;
}

/// Motion "Splash write-on": the Dal writes itself once.
/// Shows the finished mark immediately when animations are disabled.
class DalWriteOn extends StatefulWidget {
  const DalWriteOn({
    super.key,
    this.size = 96,
    this.color,
    this.delay = Duration.zero,
  });

  final double size;
  final Color? color;
  final Duration delay;

  @override
  State<DalWriteOn> createState() => _DalWriteOnState();
}

class _DalWriteOnState extends State<DalWriteOn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DaftarMotion.write,
  );
  late final Animation<double> _p = CurvedAnimation(
    parent: _c,
    curve: DaftarMotion.emphasized,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DaftarMotion.reduced(context)) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _p,
      builder: (context, _) =>
          DalMark(size: widget.size, color: widget.color, progress: _p.value),
    );
  }
}
