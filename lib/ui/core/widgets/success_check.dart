import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../brand/dal_mark.dart';
import '../motion/daftar_motion.dart';
import '../theme/daftar_colors.dart';

/// Motion Dal → check: the Dal letter bends into a check mark. Play it when
/// something was saved. [onDone] fires once the check is complete (immediately
/// with "Remove animations" on, which shows the check straight away).
///
/// ```dart
/// SuccessCheck(onDone: () => context.pop())
/// ```
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 72, this.color, this.onDone});

  final double size;
  final Color? color;
  final VoidCallback? onDone;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DaftarMotion.slow * 2,
  );
  late final Animation<double> _morph = CurvedAnimation(
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone?.call();
      });
    } else {
      _c.forward().whenComplete(() {
        if (mounted) widget.onDone?.call();
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
    final color = widget.color ?? context.colors.lime;
    return Semantics(
      label: 'Saved',
      image: true,
      child: AnimatedBuilder(
        animation: _morph,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: DalCheckPainter(progress: _morph.value, color: color),
        ),
      ),
    );
  }
}

/// Paints the Dal stroke ([progress] = 0) morphing into a check mark (1).
class DalCheckPainter extends CustomPainter {
  DalCheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const int _samples = 48;

  /// Check mark in the same 120 × 120 design box as the Dal.
  static Path checkPath() => Path()
    ..moveTo(34, 64)
    ..lineTo(54, 84)
    ..lineTo(90, 40);

  static List<Offset> _sample(Path path) {
    final metric = path.computeMetrics().first;
    return [
      for (var i = 0; i <= _samples; i++)
        metric.getTangentForOffset(metric.length * i / _samples)!.position,
    ];
  }

  static final List<Offset> _dal = _sample(DalPainter.designPath());
  static final List<Offset> _check = _sample(checkPath());

  /// The morphed polyline at [t] (0..1), in design-box coordinates.
  static List<Offset> pointsAt(double t) => [
    for (var i = 0; i <= _samples; i++)
      Offset.lerp(_dal[i], _check[i], t.clamp(0.0, 1.0))!,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 120);
    final pts = pointsAt(progress);
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = lerpDouble(16, 14, progress)!
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(DalCheckPainter old) =>
      old.progress != progress || old.color != color;
}
