import 'package:flutter/material.dart';

import 'daftar_colors.dart';
import 'daftar_tokens.dart';
import 'daftar_typography.dart';

/// Builds the Material 3 theme from Daftar tokens. Dark is the default.
abstract final class AppTheme {
  static ThemeData dark() => _build(Brightness.dark, DaftarColors.dark);
  static ThemeData light() => _build(Brightness.light, DaftarColors.light);

  static ThemeData _build(Brightness brightness, DaftarColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.lime,
      onPrimary: c.onLime,
      secondary: c.raised,
      onSecondary: c.text,
      error: c.coral,
      onError: c.onLime,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      outline: c.line,
      outlineVariant: c.line,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.raised,
    );
    final text = DaftarType.textTheme(c.text, c.muted);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      fontFamily: DaftarType.family,
      fontFamilyFallback: DaftarType.fallback,
      textTheme: text,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      // Android predictive back.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.lime,
          foregroundColor: c.onLime,
          minimumSize: const Size(64, 56),
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonR),
          textStyle: text.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(64, 56),
          side: BorderSide(color: c.line),
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonR),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.raised,
        hintStyle: text.bodyMedium?.copyWith(color: c.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
        border: const OutlineInputBorder(
          borderRadius: Radii.inputR,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.inputR,
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.inputR,
          borderSide: BorderSide(color: c.lime, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.raised,
        selectedColor: c.lime.withValues(alpha: 0.12),
        side: BorderSide(color: c.line),
        shape: const RoundedRectangleBorder(borderRadius: Radii.chipR),
        labelStyle: text.labelMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetR),
        showDragHandle: true,
        dragHandleColor: c.line,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.raised,
        contentTextStyle: text.bodyMedium,
        shape: const RoundedRectangleBorder(borderRadius: Radii.pillR),
      ),
    );
  }
}
