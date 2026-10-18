import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/offer_rows.dart';

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

/// Colours of the lines, from tokens only: the store that wins is lime-ish, the
/// rest are neutrals/amber; a legend (and dashes) keep it readable without colour.
List<Color> chartColors(DaftarColors c) => [c.text, c.amber, c.muted, c.text];

/// Price history per store.
class PriceHistoryChart extends StatelessWidget {
  const PriceHistoryChart({super.key, required this.series, this.height = 200});

  final List<ChartSeries> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (series.isEmpty) return const SizedBox.shrink();
    final palette = chartColors(c);
    final lineColors = <Color>[];
    var next = 0;
    for (final s in series) {
      lineColors.add(
        s.isBest ? c.accentText : palette[next++ % palette.length],
      );
    }

    final all = [for (final s in series) ...s.points];
    final minX = all
        .map((p) => p.at.millisecondsSinceEpoch)
        .reduce((a, b) => a < b ? a : b)
        .toDouble();
    var maxX = all
        .map((p) => p.at.millisecondsSinceEpoch)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    if (maxX == minX) maxX = minX + const Duration(days: 1).inMilliseconds;
    var minY = all.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    var maxY = all.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) == 0
        ? (maxY == 0 ? 1.0 : maxY * 0.1)
        : (maxY - minY) * 0.15;
    minY = (minY - pad).clamp(0, double.infinity);
    maxY += pad;

    final label = Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11);
    final xInterval = (maxX - minX) / 3;

    final chart = LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 3,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.line, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: (maxY - minY) / 3,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(value.toStringAsFixed(2), style: label),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: xInterval,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                final at = DateTime.fromMillisecondsSinceEpoch(value.round());
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${at.day} ${_months[at.month - 1]}',
                    style: label,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.raised,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${series[spot.barIndex].label}\n${spot.y.toStringAsFixed(3)}',
                  TextStyle(
                    color: lineColors[spot.barIndex],
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (var i = 0; i < series.length; i++)
            LineChartBarData(
              spots: [
                for (final p in series[i].points)
                  FlSpot(p.at.millisecondsSinceEpoch.toDouble(), p.value),
              ],
              color: lineColors[i],
              barWidth: series[i].isBest ? 3 : 2,
              isStrokeCapRound: true,
              dashArray: i >= 3 ? const [6, 4] : null,
              dotData: FlDotData(show: series[i].points.length <= 8),
              isCurved: false,
            ),
        ],
      ),
      duration: Duration.zero,
    );

    final box = SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: Space.sm, top: Space.sm),
        child: chart,
      ),
    );

    return Semantics(
      label:
          'Price history chart: ${series.map((s) => '${s.label}, ${s.points.length} prices').join('; ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DaftarMotion.reduced(context)
              ? box
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: DaftarMotion.write,
                  curve: DaftarMotion.emphasized,
                  builder: (context, t, child) => ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: child,
                    ),
                  ),
                  child: box,
                ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.xs,
            children: [
              for (var i = 0; i < series.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: lineColors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Space.xs + 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        series[i].label,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
