import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../domain/models/product.dart';
import '../../../../core/motion/daftar_motion.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';

/// "Size (optional)" style label above a field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.optional = false});

  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        text: text,
        style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        children: [
          if (optional)
            const TextSpan(
              text: ' (optional)',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
        ],
      ),
    );
  }
}

/// The 44 × 26 pill switch of the brand board; the thumb springs across.
/// Lime when on. [enabled] false greys it out (e.g. "I bought it").
class DaftarSwitch extends StatelessWidget {
  const DaftarSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final bool enabled;

  static const double _width = 44;
  static const double _height = 26;
  static const double _thumb = 20;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final duration = DaftarMotion.reduced(context)
        ? Duration.zero
        : SpringCurve(DaftarMotion.bouncy).duration;
    return Semantics(
      container: true,
      toggled: value,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? () => onChanged(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged(!value);
              }
            : null,
        child: SizedBox(
          width: _width + Space.lg,
          height: Chrome.minTouch,
          child: Center(
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: AnimatedContainer(
                duration: DaftarMotion.reduced(context)
                    ? Duration.zero
                    : DaftarMotion.base,
                curve: DaftarMotion.standard,
                width: _width,
                height: _height,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? c.lime : c.line,
                  borderRadius: Radii.pillR,
                ),
                child: AnimatedAlign(
                  duration: duration,
                  curve: SpringCurve(DaftarMotion.bouncy),
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      color: value ? c.onLime : c.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label + switch row (50 px) with an optional hint line.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.hint,
    this.enabled = true,
    this.bottomBorder = true,
  });

  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool bottomBorder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: bottomBorder
            ? Border(bottom: BorderSide(color: c.raised))
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.titleMedium?.copyWith(
                        fontSize: 15,
                        color: enabled ? c.text : c.muted,
                      ),
                    ),
                    if (hint != null)
                      Text(hint!, style: t.bodySmall?.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ),
            DaftarSwitch(
              value: value,
              onChanged: onChanged,
              label: title,
              enabled: enabled,
            ),
          ],
        ),
      ),
    );
  }
}

/// The g / kg / ml / L / pc segmented control with a sliding indicator.
class UnitSegmented extends StatelessWidget {
  const UnitSegmented({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final SizeUnit value;
  final ValueChanged<SizeUnit> onChanged;

  static String symbol(SizeUnit unit) => switch (unit) {
    SizeUnit.g => 'g',
    SizeUnit.kg => 'kg',
    SizeUnit.ml => 'ml',
    SizeUnit.l => 'L',
    SizeUnit.pc => 'pc',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    const units = SizeUnit.values;
    final index = units.indexOf(value);
    final reduced = DaftarMotion.reduced(context);
    return Semantics(
      container: true,
      label: 'Unit',
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.inputR,
          border: Border.all(color: c.line),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: reduced
                  ? Duration.zero
                  : SpringCurve(DaftarMotion.spatial).duration,
              curve: SpringCurve(DaftarMotion.spatial),
              alignment: Alignment(-1 + 2 * index / (units.length - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / units.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final unit in units)
                  Expanded(
                    child: Semantics(
                      container: true,
                      button: true,
                      selected: unit == value,
                      label: symbol(unit),
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(unit);
                        },
                        child: Center(
                          child: Text(
                            symbol(unit),
                            style: t.labelMedium?.copyWith(
                              fontSize: 14,
                              color: unit == value ? c.text : c.muted,
                              fontWeight: unit == value
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A 52 px raised text field matching the brand board (product, note, …).
InputDecoration boardInput(
  BuildContext context, {
  String? hint,
  String? errorText,
}) {
  final c = context.colors;
  return InputDecoration(
    hintText: hint,
    errorText: errorText,
    errorStyle: TextStyle(color: c.coral),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: Space.lg - 2,
      vertical: Space.md + 2,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: Radii.inputR,
      borderSide: BorderSide(color: c.line),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: Radii.inputR,
      borderSide: BorderSide(color: c.coral),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: Radii.inputR,
      borderSide: BorderSide(color: c.coral, width: 1.5),
    ),
  );
}

/// Paints a dashed rounded border (the "Global" / "+ Variant" style of the board).
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = Radii.input,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedPainter(color: color, radius: radius),
    child: child,
  );
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius;
}
