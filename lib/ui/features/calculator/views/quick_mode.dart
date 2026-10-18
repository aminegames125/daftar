import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/calc/calc_expression.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../view_models/calculator_providers.dart';
import 'calc_keypad.dart';

/// Quick mode: expression + live TND result, the last few results, the keypad.
///
/// With [onInsert] set (the screen was opened to pick an amount) a lime
/// "Insert into price field" button hands the current result back.
class QuickMode extends ConsumerWidget {
  const QuickMode({super.key, this.onInsert});

  final ValueChanged<Money>? onInsert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(quickCalcProvider);
    final vm = ref.read(quickCalcProvider.notifier);
    final result = state.result;
    final value = result?.value;
    final picking = onInsert != null;

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.md,
            ),
            child: Column(
              children: [
                Expanded(
                  child: _Display(expression: state.expression, result: result),
                ),
                if (state.history.isNotEmpty)
                  _History(
                    values: state.history,
                    onRecall: vm.recall,
                    onClear: vm.clearHistory,
                  ),
                if (picking) ...[
                  const SizedBox(height: Space.sm),
                  SizedBox(
                    width: double.infinity,
                    height: Chrome.minTouch,
                    child: FilledButton.icon(
                      onPressed: value == null
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              onInsert!(value);
                            },
                      icon: const Icon(Icons.input_rounded),
                      label: const Text(
                        'Insert into price field',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Space.sm),
                CalcKeypad(
                  onKey: vm.press,
                  onEquals: vm.equals,
                  equalsIsPrimary: !picking,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Display extends StatelessWidget {
  const _Display({required this.expression, required this.result});

  final String expression;
  final CalcResult? result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final value = result?.value;
    final error = result != null && !result!.isOk;
    final resultText = value?.format() ?? '0.000';

    return Semantics(
      liveRegion: true,
      label: error
          ? result!.issueMessage
          : 'Result ${value?.formatWithCode() ?? 'zero'}',
      excludeSemantics: true,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                expression.isEmpty ? ' ' : expression,
                maxLines: 1,
                style: DaftarType.price(24, c.muted).copyWith(letterSpacing: 0),
              ),
            ),
            const SizedBox(height: Space.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    resultText,
                    maxLines: 1,
                    style: DaftarType.price(
                      48,
                      value == null ? c.line : c.text,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    Currency.tnd.code,
                    style: DaftarType.price(
                      18,
                      c.muted,
                    ).copyWith(letterSpacing: 0),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: Space.xxl,
              child: error
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        result!.issueMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: c.coral),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({
    required this.values,
    required this.onRecall,
    required this.onClear,
  });

  final List<Money> values;
  final ValueChanged<Money> onRecall;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: Chrome.minTouch,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: true,
              itemCount: values.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (context, i) {
                final m = values[i];
                return Semantics(
                  button: true,
                  label: 'Recall ${m.formatWithCode()}',
                  excludeSemantics: true,
                  child: Center(
                    child: ActionChip(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onRecall(m);
                      },
                      label: Text(
                        m.format(),
                        style: t.labelLarge?.copyWith(
                          fontFeatures: DaftarType.tabular,
                        ),
                      ),
                      backgroundColor: c.surface,
                      side: BorderSide(color: c.line),
                      shape: const RoundedRectangleBorder(
                        borderRadius: Radii.chipR,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Clear history',
            onPressed: onClear,
            icon: Icon(Icons.history_toggle_off_rounded, color: c.muted),
          ),
        ],
      ),
    );
  }
}
