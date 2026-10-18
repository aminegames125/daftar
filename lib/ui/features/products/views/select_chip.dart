import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// A choice chip: selected = lime 12% fill + lime border +
/// lime text + check; a dashed-look "+ New" variant for adders.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.isAdd = false,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// A "+ Variant" style chip: muted text, no selection.
  final bool isAdd;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = selected ? c.accentText : (isAdd ? c.muted : c.text);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        // 48 px touch target around a 36 px chip.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Chrome.minTouch),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: DaftarMotion.reduced(context)
                  ? Duration.zero
                  : DaftarMotion.fast,
              curve: DaftarMotion.standard,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
              decoration: BoxDecoration(
                color: selected
                    ? c.lime.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? c.lime : c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 16, color: fg),
                    const SizedBox(width: Space.xs + 2),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: Space.xs + 2),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(
                        color: fg,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
