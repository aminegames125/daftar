import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// Motion barcode laser: a lime line sweeps up and down inside the scan frame,
/// with white corner brackets. With "Remove animations" on, the line rests in
/// the middle (the final frame).
class BarcodeLaser extends StatefulWidget {
  const BarcodeLaser({super.key, this.size = const Size(280, 190)});

  final Size size;

  @override
  State<BarcodeLaser> createState() => _BarcodeLaserState();
}

class _BarcodeLaserState extends State<BarcodeLaser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DaftarMotion.reduced(context)) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            size: widget.size,
            painter: _LaserPainter(
              progress: Curves.easeInOut.transform(_controller.value),
              laser: c.lime,
              frame: c.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _LaserPainter extends CustomPainter {
  _LaserPainter({
    required this.progress,
    required this.laser,
    required this.frame,
  });

  final double progress;
  final Color laser;
  final Color frame;

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 28.0;
    final corners = Paint()
      ..color = frame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const r = Radii.card;
    final rect = Offset.zero & size;

    // Corner brackets.
    final path = Path()
      ..moveTo(0, arm + r)
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..lineTo(arm + r, 0)
      ..moveTo(size.width - arm - r, 0)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))
      ..lineTo(size.width, arm + r)
      ..moveTo(size.width, size.height - arm - r)
      ..lineTo(size.width, size.height - r)
      ..arcToPoint(
        Offset(size.width - r, size.height),
        radius: const Radius.circular(r),
      )
      ..lineTo(size.width - arm - r, size.height)
      ..moveTo(arm + r, size.height)
      ..lineTo(r, size.height)
      ..arcToPoint(Offset(0, size.height - r), radius: const Radius.circular(r))
      ..lineTo(0, size.height - arm - r);
    canvas.drawPath(path, corners);

    // The laser: a soft glow around a crisp line.
    final y = 12 + (size.height - 24) * progress;
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          laser.withValues(alpha: 0),
          laser.withValues(alpha: 0.28),
          laser.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 22, size.width, 44));
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(r)));
    canvas.drawRect(Rect.fromLTWH(0, y - 22, size.width, 44), glow);
    canvas.drawLine(
      Offset(14, y),
      Offset(size.width - 14, y),
      Paint()
        ..color = laser
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LaserPainter old) =>
      old.progress != progress || old.laser != laser || old.frame != frame;
}
