import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';

/// One button of a [DaftarActionBar].
class ToolbarAction {
  const ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;

  /// Used as tooltip and screen-reader label (and as text on the primary button).
  final String label;
  final VoidCallback? onTap;
}

/// The bottom action bar of detail pages (place, product): a standard
/// Material 3 [BottomAppBar] with a few icon buttons and one lime action.
/// It replaces the nav bar on those pages: never show both.
///
/// Use it as `Scaffold(extendBody: true, bottomNavigationBar: DaftarActionBar(...))`
/// and pad scrolling content by `Chrome.contentBottomPadding`.
class DaftarActionBar extends StatelessWidget {
  const DaftarActionBar({super.key, required this.actions, this.primary});

  /// Icon buttons, left to right. Keep it to 3–4.
  final List<ToolbarAction> actions;

  /// The one lime action ("Log price"). Optional.
  final ToolbarAction? primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = primary;
    return BottomAppBar(
      height: Chrome.barHeight,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Row(
        children: [
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: Semantics(
                button: true,
                label: a.label,
                enabled: a.onTap != null,
                excludeSemantics: true,
                onTap: a.onTap,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: c.text.withValues(alpha: 0.08),
                    shape: const StadiumBorder(),
                  ),
                  tooltip: a.label,
                  iconSize: 24,
                  constraints: const BoxConstraints.tightFor(
                    width: Chrome.minTouch,
                    height: Chrome.minTouch,
                  ),
                  color: c.text,
                  disabledColor: c.muted,
                  icon: Icon(a.icon),
                  onPressed: a.onTap == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          a.onTap!();
                        },
                ),
              ),
            ),
          if (p != null)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  button: true,
                  label: p.label,
                  excludeSemantics: true,
                  onTap: p.onTap,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.lime,
                      foregroundColor: c.onLime,
                      minimumSize: const Size(Chrome.minTouch, Chrome.minTouch),
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                      shape: const StadiumBorder(),
                    ),
                    icon: Icon(p.icon, size: 20),
                    label: Text(
                      p.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: p.onTap == null
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            p.onTap!();
                          },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
