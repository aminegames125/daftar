import 'package:flutter/material.dart';

import '../../../../domain/models/map_pin.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// What a map marker looks like, as plain data. The Google map draws it into a
/// cached bitmap (`marker_bitmaps.dart`); the test placeholder draws a label.
///
/// Sizes are logical pixels and include room for the glow / shadow.
sealed class MarkerVisual {
  const MarkerVisual();

  /// Unique per picture (not per theme): the bitmap cache key.
  String get cacheKey;

  Size get size;

  /// Where the marker touches the ground, as a fraction of [size].
  Offset get anchor => const Offset(0.5, 0.5);

  /// Read aloud by TalkBack-style test finders and used by the placeholder map.
  String get semanticsLabel;

  /// Short text drawn in the marker, if any (price, count).
  String? get text => null;
}

/// Size of a price pin for [label]: the pill plus room for the glow ring.
Size pricePinSize(String label) {
  final width =
      (label.length * 9.0 + 28).clamp(52.0, 140.0) + 2 * PricePinVisual.glow;
  return Size(width, PricePinVisual.height + 2 * PricePinVisual.glow);
}

/// A price pill: normal = raised fill + line border;
/// best = lime fill with a glow ring; promo = amber outline. Stale pins are drawn
/// at 40% opacity through the marker's alpha (see [MapPin.isStale]).
class PricePinVisual extends MarkerVisual {
  const PricePinVisual(this.pin, {this.selected = false});

  static const double height = 32;
  static const double glow = 7;

  final MapPin pin;
  final bool selected;

  @override
  String get cacheKey =>
      'price:${pin.label}:${pin.isBest}:${pin.isPromo}:$selected';

  @override
  Size get size => pricePinSize(pin.label);

  @override
  String get text => pin.label;

  @override
  String get semanticsLabel => [
    pin.label,
    if (pin.isBest) 'best option',
    if (pin.isPromo) 'promo',
    if (pin.isStale) 'old price',
  ].join(', ');
}

/// A round bubble with the number of items merged into it. Lime glow if the
/// best option is inside.
class ClusterVisual extends MarkerVisual {
  const ClusterVisual({required this.count, this.hasBest = false});

  static const double bubble = 44;
  static const double room = 12;

  final int count;
  final bool hasBest;

  @override
  String get cacheKey => 'cluster:$count:$hasBest';

  @override
  Size get size => const Size.square(bubble + room * 2);

  @override
  String get text => '$count';

  @override
  String get semanticsLabel =>
      '$count places here. Tap to zoom in${hasBest ? ', includes the best option' : ''}';
}

/// A place: a round tile with its type icon.
class PlaceVisual extends MarkerVisual {
  const PlaceVisual({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  static const double tile = 44;
  static const double room = 12;

  final IconData icon;
  final String label;
  final bool selected;

  @override
  String get cacheKey => 'place:${icon.fontFamily}:${icon.codePoint}:$selected';

  @override
  Size get size => const Size.square(tile + room * 2);

  @override
  String get semanticsLabel => label;
}

/// The phone's own position: a dot with a soft ring.
class UserDotVisual extends MarkerVisual {
  const UserDotVisual();

  static const double dot = 28;

  @override
  String get cacheKey => 'user';

  @override
  Size get size => const Size.square(dot);

  @override
  String get semanticsLabel => 'Your location';
}

/// The pin that marks a place being saved or moved. Its tip is the bottom
/// centre of the picture.
class DropPinVisual extends MarkerVisual {
  const DropPinVisual();

  static const double width = 56;
  static const double height = 56;

  @override
  String get cacheKey => 'drop';

  @override
  Size get size => const Size(width, height);

  @override
  Offset get anchor => const Offset(0.5, 1);

  @override
  String get semanticsLabel => 'Place location';
}

/// The few colours markers use, taken from the active theme.
@immutable
class MarkerPalette {
  const MarkerPalette({
    required this.raised,
    required this.line,
    required this.text,
    required this.background,
    required this.lime,
    required this.onLime,
    required this.amber,
  });

  factory MarkerPalette.of(BuildContext context) {
    final c = context.colors;
    return MarkerPalette(
      raised: c.raised,
      line: c.line,
      text: c.text,
      background: c.background,
      lime: c.lime,
      onLime: c.onLime,
      amber: c.amber,
    );
  }

  final Color raised;
  final Color line;
  final Color text;
  final Color background;
  final Color lime;
  final Color onLime;
  final Color amber;

  /// Part of the bitmap cache key.
  String get key =>
      [raised, line, text, background, lime].map((c) => c.toARGB32()).join('.');

  @override
  bool operator ==(Object other) => other is MarkerPalette && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Fill / text / border of a price pill. Shared by the painter and the tests.
({Color fill, Color text, Color border, double borderWidth, bool glow})
pricePinStyle(PricePinVisual v, MarkerPalette p) {
  final pin = v.pin;
  return (
    fill: pin.isBest ? p.lime : p.raised,
    text: pin.isBest ? p.onLime : p.text,
    border: pin.isBest
        ? p.lime
        : pin.isPromo
        ? p.amber
        : (v.selected ? p.text : p.line),
    borderWidth: pin.isPromo && !pin.isBest ? 2 : 1,
    glow: pin.isBest,
  );
}

/// Used by the painter for pill corners.
const double pricePinPaddingX = Space.md;
