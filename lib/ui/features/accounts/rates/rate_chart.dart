import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/models/account.dart';
import '../../../../domain/rates/rate_math.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// History of the USD/TND rate: a line that draws in from the left.
/// Tap or drag to read a point. [entries] may come in any order.
class RateChart extends StatefulWidget {
  const RateChart({super.key, required this.entries, this.height = 180});

  final List<RateEntry> entries;
  final double height;

  @override
  State<RateChart> createState() => _RateChartState();
}

class _RateChartState extends State<RateChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: DaftarMotion.write,
  );
  bool _started = false;
  int? _selected;

  List<RateEntry> get _sorted =>
      [...widget.entries]..sort((a, b) => a.date.compareTo(b.date));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DaftarMotion.reduced(context)) {
      _draw.value = 1;
    } else if (!_started) {
      _started = true;
      _draw.forward();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  void _pick(double dx, double width, List<RateEntry> pts) {
    if (pts.isEmpty) return;
    final geo = _Geometry(pts);
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final d = (geo.x(pts[i], width) - dx).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    setState(() => _selected = best);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final pts = _sorted;
    if (pts.isEmpty) return const SizedBox.shrink();
    final sel = _selected != null && _selected! < pts.length
        ? pts[_selected!]
        : pts.last;
    final label = TextStyle(
      fontSize: 11,
      color: c.muted,
      fontFamily: t.bodySmall?.fontFamily,
    );

    return Semantics(
      label:
          'Rate history chart, ${pts.length} rates, latest '
          '${RateMath.formatRate(pts.last.tndPerUsdTenThousandths)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: RateMath.formatRate(sel.tndPerUsdTenThousandths),
                  style: t.titleMedium,
                ),
                TextSpan(text: '  ${_day(sel.date)}', style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth, pts),
                onHorizontalDragUpdate: (d) =>
                    _pick(d.localPosition.dx, box.maxWidth, pts),
                child: AnimatedBuilder(
                  animation: _draw,
                  builder: (context, _) => CustomPaint(
                    size: Size(box.maxWidth, widget.height),
                    painter: _RatePainter(
                      points: pts,
                      progress: DaftarMotion.emphasized.transform(_draw.value),
                      selected: _selected != null && _selected! < pts.length
                          ? _selected
                          : pts.length - 1,
                      line: c.text,
                      grid: c.line,
                      dot: c.accentText,
                      surface: c.surface,
                      labelStyle: label,
                      textDirection: Directionality.of(context),
                    ),
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

/// Shared scaling between data and pixels.
class _Geometry {
  _Geometry(List<RateEntry> pts) {
    minX = pts.first.date.millisecondsSinceEpoch;
    maxX = pts.last.date.millisecondsSinceEpoch;
    var lo = pts.first.tndPerUsdTenThousandths;
    var hi = lo;
    for (final p in pts) {
      lo = math.min(lo, p.tndPerUsdTenThousandths);
      hi = math.max(hi, p.tndPerUsdTenThousandths);
    }
    final pad = math.max(1, ((hi - lo) * 0.2).round());
    minY = lo - pad;
    maxY = hi + pad;
  }

  late final int minX;
  late final int maxX;
  late final int minY;
  late final int maxY;

  static const double leftPad = 44;
  static const double rightPad = Space.sm;
  static const double topPad = Space.sm;
  static const double bottomPad = 22;

  double x(RateEntry e, double width) {
    final span = width - leftPad - rightPad;
    if (maxX == minX) return leftPad + span / 2;
    return leftPad +
        span * (e.date.millisecondsSinceEpoch - minX) / (maxX - minX);
  }

  double y(int rate, double height) {
    final span = height - topPad - bottomPad;
    return topPad + span * (1 - (rate - minY) / (maxY - minY));
  }
}

class _RatePainter extends CustomPainter {
  _RatePainter({
    required this.points,
    required this.progress,
    required this.selected,
    required this.line,
    required this.grid,
    required this.dot,
    required this.surface,
    required this.labelStyle,
    required this.textDirection,
  });

  final List<RateEntry> points;
  final double progress;
  final int? selected;
  final Color line;
  final Color grid;
  final Color dot;
  final Color surface;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  void _text(Canvas canvas, String s, Offset at, {bool rightAlign = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, rightAlign ? at - Offset(tp.width, tp.height / 2) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(points);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final rate = g.minY + ((g.maxY - g.minY) * i / 2).round();
      final y = g.y(rate, size.height);
      canvas.drawLine(
        Offset(_Geometry.leftPad, y),
        Offset(size.width - _Geometry.rightPad, y),
        gridPaint,
      );
      _text(
        canvas,
        RateMath.formatRate(rate),
        Offset(_Geometry.leftPad - Space.xs, y),
        rightAlign: true,
      );
    }
    _text(
      canvas,
      _day(points.first.date),
      Offset(_Geometry.leftPad, size.height - 16),
    );
    if (points.length > 1) {
      final last = _day(points.last.date);
      final tp = TextPainter(
        text: TextSpan(text: last, style: labelStyle),
        textDirection: textDirection,
      )..layout();
      tp.paint(
        canvas,
        Offset(size.width - _Geometry.rightPad - tp.width, size.height - 16),
      );
    }

    final offsets = [
      for (final p in points)
        Offset(g.x(p, size.width), g.y(p.tndPerUsdTenThousandths, size.height)),
    ];
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final o in offsets.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    final linePaint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final reach =
        _Geometry.leftPad +
        (size.width - _Geometry.leftPad) * progress.clamp(0, 1);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, reach, size.height));
    canvas.drawPath(path, linePaint);
    for (final o in offsets) {
      canvas.drawCircle(o, 3, Paint()..color = line);
    }
    canvas.restore();

    final s = selected;
    if (s != null && offsets[s].dx <= reach) {
      canvas.drawCircle(offsets[s], 7, Paint()..color = surface);
      canvas.drawCircle(offsets[s], 5, Paint()..color = dot);
    }
  }

  @override
  bool shouldRepaint(_RatePainter old) =>
      old.points != points ||
      old.progress != progress ||
      old.selected != selected ||
      old.line != line ||
      old.dot != dot;
}
