import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/calc/calc_keys.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';

/// Motion keypad: five rows of four, every key springs in on press
/// ([Squish]) with a light haptic. Fixed row height, so it never overflows; the
/// key labels ignore big text scaling beyond 1.3 for the same reason.
///
/// [equalsIsPrimary] makes "=" the lime best action. Turn it off when the screen
/// already has a lime action of its own (the "Insert" button).
class CalcKeypad extends StatelessWidget {
  const CalcKeypad({
    super.key,
    required this.onKey,
    required this.onEquals,
    this.equalsIsPrimary = true,
  });

  final ValueChanged<CalcKey> onKey;
  final VoidCallback onEquals;
  final bool equalsIsPrimary;

  static const double keyHeight = Chrome.minTouch + Space.xs;

  @override
  Widget build(BuildContext context) {
    const rows = <List<CalcKey>>[
      [CalcKey.clear, CalcKey.backspace, CalcKey.percent, CalcKey.divide],
      [CalcKey.d7, CalcKey.d8, CalcKey.d9, CalcKey.multiply],
      [CalcKey.d4, CalcKey.d5, CalcKey.d6, CalcKey.subtract],
      [CalcKey.d1, CalcKey.d2, CalcKey.d3, CalcKey.add],
    ];
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            _Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: _Key(
                      label: key.symbol,
                      semantic: _semantic(key),
                      kind: key.isOperator || key == CalcKey.percent
                          ? _KeyKind.operator
                          : key.isDigit
                          ? _KeyKind.digit
                          : _KeyKind.control,
                      icon: key == CalcKey.backspace
                          ? Icons.backspace_outlined
                          : null,
                      onTap: () => onKey(key),
                    ),
                  ),
              ],
            ),
          _Row(
            children: [
              Expanded(
                flex: 2,
                child: _Key(
                  label: '0',
                  semantic: 'Zero',
                  kind: _KeyKind.digit,
                  onTap: () => onKey(CalcKey.d0),
                ),
              ),
              Expanded(
                child: _Key(
                  label: '.',
                  semantic: 'Decimal point',
                  kind: _KeyKind.digit,
                  onTap: () => onKey(CalcKey.dot),
                ),
              ),
              Expanded(
                child: _Key(
                  label: '=',
                  semantic: 'Equals',
                  kind: equalsIsPrimary ? _KeyKind.primary : _KeyKind.operator,
                  onTap: onEquals,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _semantic(CalcKey key) => switch (key) {
    CalcKey.add => 'Plus',
    CalcKey.subtract => 'Minus',
    CalcKey.multiply => 'Times',
    CalcKey.divide => 'Divided by',
    CalcKey.percent => 'Percent',
    CalcKey.backspace => 'Delete last',
    CalcKey.clear => 'Clear',
    CalcKey.dot => 'Decimal point',
    _ => key.symbol,
  };
}

class _Row extends StatelessWidget {
  const _Row({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: CalcKeypad.keyHeight,
    child: Row(children: children),
  );
}

enum _KeyKind { digit, operator, control, primary }

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.semantic,
    required this.kind,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String semantic;
  final _KeyKind kind;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (kind) {
      _KeyKind.digit => (c.surface, c.text),
      _KeyKind.operator => (c.raised, c.text),
      _KeyKind.control => (c.raised, c.muted),
      _KeyKind.primary => (c.lime, c.onLime),
    };
    return Padding(
      padding: const EdgeInsets.all(Space.xs / 2),
      child: Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        onTap: onTap,
        child: Squish(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: DecoratedBox(
            decoration: BoxDecoration(color: bg, borderRadius: Radii.buttonR),
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 22, color: fg)
                  : Text(
                      label,
                      style: DaftarType.price(
                        26,
                        fg,
                      ).copyWith(letterSpacing: 0),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
