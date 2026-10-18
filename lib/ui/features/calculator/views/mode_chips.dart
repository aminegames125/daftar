import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/calculator_providers.dart';
import 'quantity_roll.dart';

/// Quick → Basket → Best store → Split. Scrolls sideways when the screen is too
/// narrow, so it never overflows. The Basket chip carries the item-count badge.
/// Selection is neutral (lime is kept for the screen's one best action).
class ModeChips extends ConsumerWidget {
  const ModeChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(calculatorModeProvider);
    final basketCount = ref.watch(basketProvider.select((b) => b.itemCount));
    return SizedBox(
      height: Chrome.minTouch + Space.sm,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.xs,
        ),
        itemCount: CalculatorMode.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          final m = CalculatorMode.values[i];
          return _ModeChip(
            mode: m,
            selected: m == mode,
            badge: m == CalculatorMode.basket ? basketCount : 0,
            onTap: () => ref.read(calculatorModeProvider.notifier).select(m),
          );
        },
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final CalculatorMode mode;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = selected ? c.text : c.muted;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        button: true,
        selected: selected,
        label: mode.label,
        excludeSemantics: true,
        onTap: onTap,
        child: CountBadge(
          count: badge,
          child: Material(
            color: selected ? c.text.withValues(alpha: 0.12) : c.surface,
            shape: StadiumBorder(
              side: BorderSide(color: selected ? c.text : c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedContainer(
              duration: DaftarMotion.reduced(context)
                  ? Duration.zero
                  : DaftarMotion.fast,
              curve: DaftarMotion.standard,
              constraints: const BoxConstraints(minHeight: Chrome.minTouch),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(mode.icon, size: 18, color: fg),
                      const SizedBox(width: Space.sm),
                      Text(
                        mode.label,
                        maxLines: 1,
                        style: t.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
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
    );
  }
}
