import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/squish.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';

/// Motion collapsing header: a big title (with optional subtitle and
/// [background]) that shrinks into a compact top bar as the page scrolls.
///
/// A sliver: put it first in a `CustomScrollView`.
///
/// ```dart
/// CustomScrollView(slivers: [
///   CollapsingHeader(
///     title: 'Café El Houma',
///     subtitle: 'Open now · until 22:00',
///     leading: HeaderIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: context.pop),
///     actions: [HeaderIconButton(icon: Icons.edit_outlined, label: 'Edit', onTap: edit)],
///     background: Image.file(photo, fit: BoxFit.cover),
///   ),
///   SliverList(...),
/// ])
/// ```
class CollapsingHeader extends StatelessWidget {
  const CollapsingHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.background,
    this.expandedHeight = 168,
  });

  final String title;
  final String? subtitle;

  /// Usually a back button. Sits at the start of the compact bar.
  final Widget? leading;

  /// Trailing buttons of the compact bar.
  final List<Widget> actions;

  /// Painted behind the expanded header (photo, gradient). It fades out as the
  /// header collapses, leaving the plain page background.
  final Widget? background;

  /// Height of the expanded header *below* the status bar.
  final double expandedHeight;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _HeaderDelegate(
        title: title,
        subtitle: subtitle,
        leading: leading,
        actions: actions,
        background: background,
        topInset: topInset,
        expanded: expandedHeight,
        textScale: MediaQuery.textScalerOf(context),
      ),
    );
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.actions,
    required this.background,
    required this.topInset,
    required this.expanded,
    required this.textScale,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? background;
  final double topInset;
  final double expanded;
  final TextScaler textScale;

  static const double _bar = kToolbarHeight;
  static const double _collapsedTitleScale = 0.64;

  @override
  double get minExtent => topInset + _bar;

  @override
  double get maxExtent => topInset + math.max(expanded, _bar);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final range = maxExtent - minExtent;
    final p = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    final leadingWidth = leading == null
        ? Space.gutter
        : Space.gutter + Chrome.minTouch + Space.xs;
    final titleStyle = t.headlineLarge!;
    // Expanded: title sits at the bottom. Collapsed: vertically centred in the bar.
    final subtitleHeight = subtitle == null ? 0.0 : 22.0 * (1 - p);
    final expandedTop =
        maxExtent - shrinkOffset - 34 - subtitleHeight - Space.lg;
    final collapsedTop = topInset + (_bar - 34 * _collapsedTitleScale) / 2;
    final titleTop =
        collapsedTop +
        (expandedTop.clamp(collapsedTop, double.infinity) - collapsedTop) *
            (1 - p);
    final scale = 1 - (1 - _collapsedTitleScale) * p;
    final left = Space.gutter + (leadingWidth - Space.gutter) * p;

    return Semantics(
      header: true,
      container: true,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: c.background),
            if (background != null) Opacity(opacity: 1 - p, child: background),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 1,
              child: Opacity(
                opacity: p,
                child: ColoredBox(color: c.line),
              ),
            ),
            Positioned(
              left: left,
              right:
                  Space.gutter +
                  actions.length * (Chrome.minTouch + Space.xs) * p,
              top: titleTop,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ),
            if (subtitle != null)
              Positioned(
                left: Space.gutter,
                right: Space.gutter,
                bottom: Space.lg,
                child: Opacity(
                  opacity: (1 - p * 2).clamp(0.0, 1.0),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                ),
              ),
            Positioned(
              left: Space.sm,
              right: Space.sm,
              top: topInset,
              height: _bar,
              child: Row(children: [?leading, const Spacer(), ...actions]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.title != title ||
      old.subtitle != subtitle ||
      old.leading != leading ||
      old.actions != actions ||
      old.background != background ||
      old.topInset != topInset ||
      old.expanded != expanded ||
      old.textScale != textScale;
}

/// 48 px round icon button for headers (back, edit, …). Has a tooltip and a
/// screen-reader label.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: Squish(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox.square(
            dimension: Chrome.minTouch,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.raised.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
