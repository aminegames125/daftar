import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/daftar_motion.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';

class NavDestination {
  const NavDestination({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// The bottom navigation of the four main tabs, built on the Material 3
/// Expressive "flexible navigation bar" (horizontal configuration): a flat bar
/// where the selected tab grows into a pill holding its icon and label side by
/// side, and the other tabs show only their icon.
///
/// Flutter has no official widget for this bar yet, so it is made from Material
/// parts ([Material], [InkWell], [AnimatedContainer]). Overflow cannot happen
/// by design: the pill widths are worked out from the bar width and always add
/// up to it, the label is one ellipsized line, and text scaling is capped.
///
/// Detail pages use a [DaftarActionBar] instead: never both at once
///. The lime "+" is a [QuickAddFab] given to
/// sits inside this bar.
class DaftarNavBar extends StatelessWidget {
  const DaftarNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required this.onAdd,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// Called by the lime "+" sitting in the middle of the bar.
  final VoidCallback onAdd;

  /// Height of a tab pill; at least a comfortable touch target.
  static const double _pill = Chrome.minTouch;

  /// Radius of the round notch cut into the bar around the "+", and the width
  /// the tabs must leave free in the middle.
  static const double _notch = Chrome.fabSize / 2 + 5;
  static const double _gap = 2 * _notch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = destinations.length;
    final duration = DaftarMotion.reduced(context)
        ? Duration.zero
        : DaftarMotion.base;
    const bar = Chrome.barHeight - 2 * Space.sm;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: Chrome.barHeight + Chrome.fabRise,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The floating pill with the four tabs.
            Positioned(
              left: Space.md,
              right: Space.md,
              bottom: Space.sm,
              height: bar,
              child: Material(
                color: c.surface,
                elevation: 3,
                shadowColor: Colors.black,
                surfaceTintColor: Colors.transparent,
                shape: const _NotchedPill(
                  notchRadius: _notch,
                  notchCenterY: bar / 2 - Chrome.fabRise,
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // The "+" takes a fixed gap exactly in the middle, so each
                      // half has the same width. In a half the selected tab takes
                      // what its neighbour leaves; with no selection there the two
                      // tabs share it equally. Widths always sum to the bar width.
                      final half = (box.maxWidth - _gap) / 2;
                      final perHalf = (n / 2).floor();
                      final small = (half * 0.34).clamp(44.0, half / perHalf);
                      double widthOf(int i) {
                        final start = (i ~/ perHalf) * perHalf;
                        final sel = currentIndex - start;
                        if (sel < 0 || sel >= perHalf) return half / perHalf;
                        return i == currentIndex
                            ? half - small * (perHalf - 1)
                            : small;
                      }

                      return Row(
                        children: [
                          for (var i = 0; i < n; i++) ...[
                            if (i == perHalf) const SizedBox(width: _gap),
                            _Tab(
                              destination: destinations[i],
                              selected: i == currentIndex,
                              width: widthOf(i),
                              duration: duration,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onSelect(i);
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            // The lime "+" rises out of the middle of the pill, sitting in the
            // notch cut into its top edge.
            Positioned(
              left: 0,
              right: 0,
              bottom: Space.sm + (bar - Chrome.fabSize) / 2 + Chrome.fabRise,
              child: Center(child: QuickAddFab(onPressed: onAdd)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.destination,
    required this.selected,
    required this.width,
    required this.duration,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final double width;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.text : c.muted;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        excludeSemantics: true,
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          curve: DaftarMotion.standard,
          width: width,
          height: DaftarNavBar._pill,
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: selected
                ? c.text.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(destination.icon, size: 24, color: fg),
                    if (selected) ...[
                      const SizedBox(width: Space.xs),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(right: Space.xs),
                          child: Text(
                            destination.label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lime "+" of the main tabs (the one best action), set in the middle of
/// the [DaftarNavBar]. It is a [Chrome.fabSize] circle.
class QuickAddFab extends StatelessWidget {
  const QuickAddFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Quick add',
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: 'Quick add',
        child: Material(
          color: c.lime,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              onPressed();
            },
            child: SizedBox.square(
              dimension: Chrome.fabSize,
              child: Icon(Icons.add_rounded, size: 30, color: c.onLime),
            ),
          ),
        ),
      ),
    );
  }
}

/// A stadium-shaped bar with a round notch bitten out of its top edge for the
/// "+", the notch's two corners rounded off with a small fillet.
class _NotchedPill extends ShapeBorder {
  const _NotchedPill({required this.notchRadius, required this.notchCenterY});

  final double notchRadius;

  /// Height of the notch centre below the bar's top edge (may be small).
  final double notchCenterY;

  static const double _fillet = 12;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final w = rect.width;
    final h = rect.height;
    final r = h / 2;
    final cx = w / 2;
    const f = _fillet;
    final n = notchRadius;
    final cy = notchCenterY;
    // Fillet circles sit at height f, touching the top edge and the notch.
    final dx = math.sqrt(math.pow(n + f, 2) - math.pow(f - cy, 2));
    final tilt = Offset(dx, f - cy) / (n + f);
    final leftTouch = Offset(cx - tilt.dx * n, cy + tilt.dy * n);
    final rightTouch = Offset(cx + tilt.dx * n, cy + tilt.dy * n);
    const fr = Radius.circular(f);
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(cx - dx, 0)
      ..arcToPoint(leftTouch, radius: fr)
      ..arcToPoint(rightTouch, radius: Radius.circular(n), clockwise: false)
      ..arcToPoint(Offset(cx + dx, 0), radius: fr)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, r), radius: Radius.circular(r))
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
    return path.shift(rect.topLeft);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}
