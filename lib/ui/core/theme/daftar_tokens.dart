import 'package:flutter/widgets.dart';

/// Spacing scale (4 pt grid). The app's visual tokens.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Side gutter of every screen.
  static const double gutter = 20;
}

/// Corner radii. Pills use [full].
abstract final class Radii {
  static const double chip = 8;
  static const double input = 14;
  static const double button = 18;
  static const double card = 24;
  static const double sheet = 30;
  static const double full = 999;

  static const BorderRadius chipR = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius inputR = BorderRadius.all(Radius.circular(input));
  static const BorderRadius buttonR = BorderRadius.all(Radius.circular(button));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetR = BorderRadius.all(Radius.circular(sheet));
  static const BorderRadius pillR = BorderRadius.all(Radius.circular(full));
}

/// Fixed sizes of the bottom chrome (Material 3 navigation / action bar).
abstract final class Chrome {
  /// Height of the navigation bar and the action bar (Material 3 default).
  static const double barHeight = 80;

  /// Diameter of the lime "+" button.
  static const double fabSize = 60;

  /// How far the "+" rises above the middle of the nav bar.
  static const double fabRise = 20;

  /// Breathing room under full-screen content that has no bar.
  static const double barBottom = 16;

  /// Space to leave under scrolling content so the last item clears the bar
  /// (detail pages) or the "+" button (main tabs, whose body ends above the bar).
  static const double contentBottomPadding = barHeight + Space.xxl;

  /// Minimum touch target.
  static const double minTouch = 48;
}
