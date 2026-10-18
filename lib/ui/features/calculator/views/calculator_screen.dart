import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/calculator_providers.dart';
import 'basket_mode.dart';
import 'best_store_mode.dart';
import 'mode_chips.dart';
import 'quick_mode.dart';
import 'split_mode.dart';

/// The Calculator tab: a title, the mode chips and the body of the chosen mode.
/// Each mode lives in its own file; this widget only switches between them.
///
/// With [pick] true (route `Routes.calculatorPick`) it is a full-screen picker:
/// Quick mode only, with an "Insert into price field" action that pops the
/// result as a [Money].
class CalculatorScreen extends ConsumerWidget {
  const CalculatorScreen({super.key, this.pick = false});

  final bool pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final mode = ref.watch(calculatorModeProvider);

    final body = pick
        ? QuickMode(onInsert: (m) => context.pop(m))
        : switch (mode) {
            CalculatorMode.quick => const QuickMode(),
            CalculatorMode.basket => const BasketMode(),
            CalculatorMode.bestStore => const BestStoreMode(),
            CalculatorMode.split => const SplitMode(),
          };

    final content = SafeArea(
      bottom: pick,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.lg,
              Space.gutter,
              Space.xs,
            ),
            child: Row(
              children: [
                if (pick)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.sm),
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: () => context.pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: context.colors.text,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    'Calculator',
                    style: t.headlineLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!pick)
                  IconButton(
                    tooltip: 'Lists',
                    onPressed: () => context.push(Routes.lists),
                    icon: Icon(
                      Icons.checklist_rounded,
                      color: context.colors.text,
                    ),
                  ),
              ],
            ),
          ),
          if (!pick) const ModeChips(),
          Expanded(child: body),
        ],
      ),
    );

    return pick ? Scaffold(body: content) : content;
  }
}
