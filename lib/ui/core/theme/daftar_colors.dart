import 'package:flutter/material.dart';

/// Daftar colour tokens. The app's visual tokens.
///
/// Read them with `context.colors` (see [DaftarColorsX]). Never hard-code hex
/// values in widgets.
@immutable
class DaftarColors extends ThemeExtension<DaftarColors> {
  const DaftarColors({
    required this.background,
    required this.surface,
    required this.raised,
    required this.line,
    required this.muted,
    required this.text,
    required this.lime,
    required this.limePressed,
    required this.onLime,
    required this.accentText,
    required this.amber,
    required this.coral,
    required this.glass,
    required this.glassBorder,
  });

  /// Page background ("Ink" in dark, "Paper" in light).
  final Color background;

  /// Cards, sheets.
  final Color surface;

  /// Inputs, chips, secondary buttons.
  final Color raised;

  /// Borders and dividers.
  final Color line;

  /// Secondary text.
  final Color muted;

  /// Primary text.
  final Color text;

  /// The one action / the best answer on a screen. Never decoration.
  final Color lime;
  final Color limePressed;

  /// Text and icons drawn on top of [lime].
  final Color onLime;

  /// Lime-coloured *text*: lime in dark mode, olive in light (for contrast).
  final Color accentText;

  /// Promos, warnings.
  final Color amber;

  /// Price went up, delete, errors.
  final Color coral;

  /// Fill of floating glass surfaces (nav pill, toolbars, toasts).
  final Color glass;
  final Color glassBorder;

  static const dark = DaftarColors(
    background: Color(0xFF0B0D10),
    surface: Color(0xFF14171C),
    raised: Color(0xFF1C2027),
    line: Color(0xFF2A2F38),
    muted: Color(0xFF8A93A3),
    text: Color(0xFFF2F4F7),
    lime: Color(0xFFC6F432),
    limePressed: Color(0xFFA8D41F),
    onLime: Color(0xFF0B0D10),
    accentText: Color(0xFFC6F432),
    amber: Color(0xFFFFB547),
    coral: Color(0xFFFF5C5C),
    glass: Color(0xBC1C2027), // raised @ 74%
    glassBorder: Color(0x17F2F4F7), // text @ 9%
  );

  static const light = DaftarColors(
    background: Color(0xFFF6F7F4),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEEF0EA),
    line: Color(0xFFDDE1D6),
    muted: Color(0xFF5C6470),
    text: Color(0xFF0D0F12),
    lime: Color(0xFFC6F432),
    limePressed: Color(0xFFA8D41F),
    onLime: Color(0xFF0B0D10),
    accentText: Color(0xFF4F6B00),
    amber: Color(0xFFB86E00),
    coral: Color(0xFFD93636),
    glass: Color(0xBDFFFFFF), // white @ 74%
    glassBorder: Color(0x140D0F12), // text @ 8%
  );

  @override
  DaftarColors copyWith({
    Color? background,
    Color? surface,
    Color? raised,
    Color? line,
    Color? muted,
    Color? text,
    Color? lime,
    Color? limePressed,
    Color? onLime,
    Color? accentText,
    Color? amber,
    Color? coral,
    Color? glass,
    Color? glassBorder,
  }) {
    return DaftarColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      line: line ?? this.line,
      muted: muted ?? this.muted,
      text: text ?? this.text,
      lime: lime ?? this.lime,
      limePressed: limePressed ?? this.limePressed,
      onLime: onLime ?? this.onLime,
      accentText: accentText ?? this.accentText,
      amber: amber ?? this.amber,
      coral: coral ?? this.coral,
      glass: glass ?? this.glass,
      glassBorder: glassBorder ?? this.glassBorder,
    );
  }

  @override
  DaftarColors lerp(ThemeExtension<DaftarColors>? other, double t) {
    if (other is! DaftarColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DaftarColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      line: l(line, other.line),
      muted: l(muted, other.muted),
      text: l(text, other.text),
      lime: l(lime, other.lime),
      limePressed: l(limePressed, other.limePressed),
      onLime: l(onLime, other.onLime),
      accentText: l(accentText, other.accentText),
      amber: l(amber, other.amber),
      coral: l(coral, other.coral),
      glass: l(glass, other.glass),
      glassBorder: l(glassBorder, other.glassBorder),
    );
  }
}

extension DaftarColorsX on BuildContext {
  DaftarColors get colors => Theme.of(this).extension<DaftarColors>()!;
}
