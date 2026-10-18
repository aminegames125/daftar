import 'package:flutter/material.dart';

/// Typography. The app's visual tokens.
///
/// Interface text uses Plus Jakarta Sans. Anything the user types may be
/// Arabic, so IBM Plex Sans Arabic is always the fallback family.
abstract final class DaftarType {
  static const String family = 'PlusJakartaSans';
  static const List<String> fallback = ['IBMPlexSansArabic'];

  /// Tabular figures so prices line up digit by digit.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextTheme textTheme(Color text, Color muted) {
    TextStyle s(
      double size,
      FontWeight w, {
      double? height,
      double ls = 0,
      Color? c,
    }) => TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      fontWeight: w,
      height: height,
      letterSpacing: ls,
      color: c ?? text,
    );

    return TextTheme(
      displayLarge: s(56, FontWeight.w800, height: 1.0, ls: -2.2),
      displayMedium: s(44, FontWeight.w800, height: 1.05, ls: -1.6),
      displaySmall: s(34, FontWeight.w800, height: 1.1, ls: -1.0),
      headlineLarge: s(28, FontWeight.w800, height: 1.15, ls: -0.8),
      headlineMedium: s(24, FontWeight.w700, height: 1.2, ls: -0.5),
      headlineSmall: s(20, FontWeight.w700, height: 1.25, ls: -0.4),
      titleLarge: s(18, FontWeight.w700, height: 1.3, ls: -0.2),
      titleMedium: s(16, FontWeight.w600, height: 1.35),
      titleSmall: s(14, FontWeight.w600, height: 1.4),
      bodyLarge: s(16, FontWeight.w400, height: 1.5),
      bodyMedium: s(15, FontWeight.w400, height: 1.5),
      bodySmall: s(13, FontWeight.w500, height: 1.45, c: muted),
      labelLarge: s(15, FontWeight.w700, height: 1.2),
      labelMedium: s(13, FontWeight.w600, height: 1.2),
      labelSmall: s(11, FontWeight.w700, height: 1.2, ls: 0.6, c: muted),
    );
  }

  /// Big price, e.g. "4.400". Pair with a smaller muted "TND".
  static TextStyle price(double size, Color color) => TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: size,
    fontWeight: FontWeight.w800,
    letterSpacing: -size * 0.04,
    height: 1.0,
    color: color,
    fontFeatures: tabular,
  );
}
