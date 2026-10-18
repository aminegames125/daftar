import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../motion/daftar_motion.dart';
import '../motion/squish.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';
import 'glass_surface.dart';

/// One entry of a [GlassLongPressMenu].
class GlassMenuAction {
  const GlassMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Draws the entry in coral. Use it for "Delete" / "Hide" and confirm afterwards.
  final bool destructive;
}

/// Motion long-press menu: hold a row and it lifts, the rest of the screen
/// dims, and a glass menu pops out next to it.
///
/// ```dart
/// GlassLongPressMenu(
///   onTap: () => context.push(Routes.placeDetail(id)),
///   actions: [
///     GlassMenuAction(icon: Icons.edit_outlined, label: 'Edit', onTap: edit),
///     GlassMenuAction(icon: Icons.delete_outline, label: 'Delete', onTap: del, destructive: true),
///   ],
///   child: MyRow(),
/// )
/// ```
class GlassLongPressMenu extends StatefulWidget {
  const GlassLongPressMenu({
    super.key,
    required this.child,
    required this.actions,
    this.onTap,
  });

  final Widget child;
  final List<GlassMenuAction> actions;

  /// Plain tap on the child (optional).
  final VoidCallback? onTap;

  @override
  State<GlassLongPressMenu> createState() => _GlassLongPressMenuState();
}

class _GlassLongPressMenuState extends State<GlassLongPressMenu> {
  final GlobalKey _boundary = GlobalKey();

  Future<void> _open() async {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || widget.actions.isEmpty) return;
    unawaited(HapticFeedback.mediumImpact());
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final lifted = ValueNotifier<ui.Image?>(null);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final reduced = DaftarMotion.reduced(context);

    // Snapshot the row so it can "lift" above the scrim; the menu does not wait for it.
    unawaited(
      _snapshot(dpr).then((image) => lifted.value = image, onError: (_) {}),
    );

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: Colors.transparent,
      transitionDuration: reduced ? Duration.zero : DaftarMotion.slow,
      pageBuilder: (dialogContext, animation, _) => GlassMenuOverlay(
        animation: animation,
        anchor: rect,
        lifted: lifted,
        actions: widget.actions,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<ui.Image?> _snapshot(double pixelRatio) async {
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    return object.toImage(pixelRatio: pixelRatio);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: _open,
      child: RepaintBoundary(key: _boundary, child: widget.child),
    );
  }
}

/// The dim + lifted row + glass menu shown by [GlassLongPressMenu]. Exposed for tests.
class GlassMenuOverlay extends StatelessWidget {
  const GlassMenuOverlay({
    super.key,
    required this.animation,
    required this.anchor,
    required this.lifted,
    required this.actions,
    required this.onClose,
  });

  final Animation<double> animation;

  /// Global rectangle of the pressed row.
  final Rect anchor;
  final ValueListenable<ui.Image?> lifted;
  final List<GlassMenuAction> actions;
  final VoidCallback onClose;

  static const double _menuWidth = 232;
  static const double _rowHeight = Chrome.minTouch;
  static const double _gap = Space.md;
  static final SpringCurve _spring = SpringCurve(DaftarMotion.bouncy);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    final menuHeight = actions.length * _rowHeight + Space.sm * 2;
    final below =
        anchor.bottom + _gap + menuHeight <=
        size.height - insets.bottom - Space.xxl;
    final left = anchor.left.clamp(
      Space.gutter,
      math.max(Space.gutter, size.width - Space.gutter - _menuWidth),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value.clamp(0.0, 1.0);
        final pop = animation.status == AnimationStatus.reverse
            ? v
            : _spring.transform(v);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: ColoredBox(
                  color: c.background.withValues(alpha: 0.7 * v),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: anchor,
              child: IgnorePointer(
                child: ValueListenableBuilder<ui.Image?>(
                  valueListenable: lifted,
                  builder: (context, image, _) {
                    if (image == null) return const SizedBox.shrink();
                    return Transform.scale(
                      scale: 1 + 0.03 * pop,
                      child: RawImage(image: image, fit: BoxFit.fill),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              left: left.toDouble(),
              top: below ? anchor.bottom + _gap : null,
              bottom: below ? null : size.height - anchor.top + _gap,
              width: _menuWidth,
              child: Opacity(
                opacity: v,
                child: Transform.scale(
                  scale: 0.7 + 0.3 * pop,
                  alignment: below ? Alignment.topLeft : Alignment.bottomLeft,
                  child: Material(
                    type: MaterialType.transparency,
                    child: GlassSurface(
                      borderRadius: Radii.cardR,
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final a in actions)
                            _MenuRow(
                              action: a,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onClose();
                                a.onTap();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.action, required this.onTap});

  final GlassMenuAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = action.destructive ? c.coral : c.text;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      onTap: onTap,
      child: Squish(
        onTap: onTap,
        pressedScale: 0.98,
        child: SizedBox(
          height: GlassMenuOverlay._rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Row(
              children: [
                Icon(action.icon, size: 20, color: color),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    action.label,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
