import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/glass_surface.dart';

/// One action of the "+" menu.
class QuickAddAction {
  const QuickAddAction({
    required this.icon,
    required this.label,
    required this.route,
  });
  final IconData icon;
  final String label;
  final String route;
}

/// Nearest to the "+" first.
final List<QuickAddAction> quickAddActions = [
  const QuickAddAction(
    icon: Icons.sell_outlined,
    label: 'Log price',
    route: Routes.logPrice,
  ),
  const QuickAddAction(
    icon: Icons.place_outlined,
    label: 'Add place',
    route: Routes.placeNew,
  ),
  const QuickAddAction(
    icon: Icons.qr_code_scanner_rounded,
    label: 'Scan barcode',
    route: Routes.scan,
  ),
  const QuickAddAction(
    icon: Icons.photo_camera_outlined,
    label: 'Snap a menu',
    route: Routes.menuSnap,
  ),
];

/// The "+" quick-add menu: the lime "+" turns into "×" and the four
/// actions spring out of it one after another. Tapping an action closes the
/// menu and pushes its route.
Future<void> showQuickAddSheet(BuildContext context) {
  final router = GoRouter.of(context);
  final reduced = DaftarMotion.reduced(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close quick add',
    barrierColor: Colors.transparent,
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 300),
    pageBuilder: (dialogContext, animation, _) => QuickAddMenu(
      animation: animation,
      onClose: () => Navigator.of(dialogContext).pop(),
      onPick: (action) {
        Navigator.of(dialogContext).pop();
        router.push(action.route);
      },
    ),
  );
}

/// The overlay content of [showQuickAddSheet]. [animation] runs 0 → 1 when
/// opening and back when closing.
class QuickAddMenu extends StatelessWidget {
  const QuickAddMenu({
    super.key,
    required this.animation,
    required this.onClose,
    required this.onPick,
    this.actions,
  });

  final Animation<double> animation;
  final VoidCallback onClose;
  final ValueChanged<QuickAddAction> onPick;
  final List<QuickAddAction>? actions;

  /// Delay between two items, as a fraction of the whole animation.
  static const double _stagger = 0.08;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = actions ?? quickAddActions;
    final inset = MediaQuery.paddingOf(context).bottom;
    // Where the "+" sits: in the middle of the floating nav bar.
    final plusBottom =
        inset +
        Space.sm +
        (Chrome.barHeight - 2 * Space.sm - Chrome.fabSize) / 2 +
        Chrome.fabRise;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value.clamp(0.0, 1.0);

        double itemProgress(int k) {
          final start = k * _stagger;
          final t = ((v - start) / (1 - start)).clamp(0.0, 1.0);
          return DaftarMotion.standard.transform(t);
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: ColoredBox(
                  color: c.background.withValues(alpha: 0.72 * v),
                ),
              ),
            ),
            Positioned(
              left: Space.lg,
              right: Space.lg,
              bottom: plusBottom + Chrome.fabSize + Space.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var k = items.length - 1; k >= 0; k--)
                    Padding(
                      padding: EdgeInsets.only(
                        top: k == items.length - 1 ? 0 : Space.md,
                      ),
                      child: _MenuItem(
                        action: items[k],
                        progress: itemProgress(k),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onPick(items[k]);
                        },
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: plusBottom,
              child: Center(
                child: Semantics(
                  button: true,
                  label: 'Close quick add',
                  child: Material(
                    color: c.lime,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        onClose();
                      },
                      child: SizedBox.square(
                        dimension: Chrome.fabSize,
                        child: Transform.rotate(
                          angle:
                              math.pi / 4 * DaftarMotion.standard.transform(v),
                          child: Icon(
                            Icons.add_rounded,
                            color: c.onLime,
                            size: 30,
                          ),
                        ),
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

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.action,
    required this.progress,
    required this.onTap,
  });

  final QuickAddAction action;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final scale = 0.9 + 0.1 * progress;
    return IgnorePointer(
      // Tappable almost at once, so the first tap is never lost.
      ignoring: progress < 0.25,
      child: Opacity(
        opacity: progress.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - progress) * Space.xxl),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Semantics(
              button: true,
              label: action.label,
              excludeSemantics: true,
              onTap: onTap,
              child: Squish(
                onTap: onTap,
                child: SizedBox(
                  width: 240,
                  child: GlassSurface(
                    height: Chrome.minTouch + Space.sm,
                    padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                    child: Row(
                      children: [
                        Icon(action.icon, size: 22, color: c.text),
                        const SizedBox(width: Space.lg),
                        Expanded(
                          child: Text(
                            action.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleSmall,
                          ),
                        ),
                      ],
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
