import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';

/// "Reading the menu" over a photo: four corner brackets snap onto
/// the menu, then a band sweeps down and lines light up as they are read.
/// Reduced motion: the brackets and a few lit lines, no movement.
class MenuScanOverlay extends StatefulWidget {
  const MenuScanOverlay({super.key});

  @override
  State<MenuScanOverlay> createState() => _MenuScanOverlayState();
}

class _MenuScanOverlayState extends State<MenuScanOverlay>
    with TickerProviderStateMixin {
  static const _period = Duration(milliseconds: 2200);

  late final AnimationController _snap = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _period,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DaftarMotion.reduced(context)) {
      _sweep.value = 0.6;
      return;
    }
    _snap.value = 0;
    _snap.animateWith(SpringSimulation(DaftarMotion.bouncy, 0, 1, 0));
    _sweep.repeat();
  }

  @override
  void dispose() {
    _snap.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Reading the menu',
      liveRegion: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([_snap, _sweep]),
        builder: (context, _) => CustomPaint(
          painter: _ScanPainter(
            snap: _snap.value,
            sweep: _sweep.value,
            color: c.lime,
          ),
        ),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({required this.snap, required this.sweep, required this.color});

  final double snap;
  final double sweep;
  final Color color;

  static const _inset = 18.0;
  static const _arm = 28.0;
  static const _lines = 9;

  @override
  void paint(Canvas canvas, Size size) {
    // Brackets start further out and spring in.
    final out = (1 - snap) * 40;
    final rect = Rect.fromLTWH(
      _inset,
      _inset,
      size.width - 2 * _inset,
      size.height - 2 * _inset,
    ).inflate(out);
    final bracket = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final (corner, dx, dy) in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner + Offset(dx * _arm, 0), bracket);
      canvas.drawLine(corner, corner + Offset(0, dy * _arm), bracket);
    }

    // Lines light up as the band passes them.
    final inner = rect.deflate(_inset);
    final bandY = inner.top + inner.height * sweep;
    for (var i = 0; i < _lines; i++) {
      final y = inner.top + inner.height * (i + 0.5) / _lines;
      final width =
          inner.width * (0.45 + 0.5 * ((math.sin(i * 12.9898) + 1) / 2));
      final lit =
          (1 - ((bandY - y) / (inner.height * 0.5)).clamp(0.0, 1.0)) *
          (y <= bandY ? 1 : 0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inner.left, y - 3, width, 6),
          const Radius.circular(3),
        ),
        Paint()..color = color.withValues(alpha: 0.10 + 0.55 * lit),
      );
    }

    // The sweeping band itself.
    canvas.drawRect(
      Rect.fromLTWH(inner.left, bandY - 1.5, inner.width, 3),
      Paint()..color = color.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.snap != snap || old.sweep != sweep || old.color != color;
}
