import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/basket.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/bill_splitter.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../../core/widgets/money_field.dart';
import '../view_models/calculator_providers.dart';
import '../view_models/split_view_model.dart';

/// Split mode: share a total equally or item by item, with tax and
/// tip, optional 0.050 TND cash rounding and a choice of who pays the remainder.
class SplitMode extends ConsumerWidget {
  const SplitMode({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basket = ref.watch(basketProvider);
    final s = ref.watch(splitProvider);
    final vm = ref.read(splitProvider.notifier);
    final outcome = computeSplit(s, basket);
    final byItem = s.style == SplitStyle.byItem;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Chrome.contentBottomPadding,
      ),
      children: [
        _Choices(
          label: 'How to split',
          options: const ['Equally', 'By item'],
          selected: byItem ? 1 : 0,
          onSelect: (i) => vm.setStyle(SplitStyle.values[i]),
        ),
        const SizedBox(height: Space.lg),
        if (!byItem) ...[
          _Choices(
            label: 'Amount',
            options: const ['Basket total', 'Type an amount'],
            selected: s.source == SplitSource.basket ? 0 : 1,
            onSelect: (i) => vm.setSource(SplitSource.values[i]),
          ),
          const SizedBox(height: Space.sm),
          if (s.source == SplitSource.typed)
            MoneyField(
              label: 'Amount to split',
              fontSize: 32,
              initialValue: s.typedAmount,
              onChanged: vm.setTyped,
            )
          else
            _BasketTotal(basket: basket),
          const SizedBox(height: Space.lg),
        ],
        _PeopleStepper(people: s.people, onChanged: vm.setPeople),
        const SizedBox(height: Space.lg),
        if (byItem && basket.isNotEmpty) ...[
          _ItemOwners(basket: basket, state: s),
          const SizedBox(height: Space.lg),
          MoneyField(
            label: 'Tax (optional)',
            fontSize: 24,
            initialValue: s.tax,
            onChanged: vm.setTax,
          ),
          const SizedBox(height: Space.sm),
          MoneyField(
            label: 'Tip (optional)',
            fontSize: 24,
            initialValue: s.tip,
            onChanged: vm.setTip,
          ),
          const SizedBox(height: Space.lg),
        ],
        _CashRounding(value: s.cashRounding, onChanged: vm.setCashRounding),
        const SizedBox(height: Space.md),
        _RemainderPicker(state: s, onSelect: vm.setRemainder),
        const SizedBox(height: Space.lg),
        _Result(state: s, outcome: outcome),
      ],
    );
  }
}

/// A labelled row of mutually exclusive pills that wraps instead of overflowing.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.bodySmall),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (var i = 0; i < options.length; i++)
              _Pill(
                label: options[i],
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = selected ? c.text : c.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? c.text.withValues(alpha: 0.12) : c.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? c.text : c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Chrome.minTouch,
              minWidth: Chrome.minTouch,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: t.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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

class _BasketTotal extends StatelessWidget {
  const _BasketTotal({required this.basket});
  final Basket basket;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    if (basket.isEmpty) {
      return Text(
        'Your basket is empty. Add items in Basket mode or type an amount.',
        style: t.bodySmall,
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            basket.itemCount == 1
                ? 'Basket · 1 item'
                : 'Basket · ${basket.itemCount} items',
            style: t.bodyMedium,
          ),
        ),
        const SizedBox(width: Space.sm),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              basket.total.formatWithCode(),
              maxLines: 1,
              style: DaftarType.price(20, c.text).copyWith(letterSpacing: 0),
            ),
          ),
        ),
      ],
    );
  }
}

class _PeopleStepper extends StatelessWidget {
  const _PeopleStepper({required this.people, required this.onChanged});
  final int people;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text('People', style: t.titleMedium)),
        _StepButton(
          icon: Icons.remove_rounded,
          label: 'One less person',
          onTap: people <= SplitState.minPeople
              ? null
              : () => onChanged(people - 1),
        ),
        SizedBox(
          width: 44,
          child: Semantics(
            label: '$people people',
            excludeSemantics: true,
            child: Center(
              child: Text(
                '$people',
                style: DaftarType.price(24, c.text).copyWith(letterSpacing: 0),
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          label: 'One more person',
          onTap: people >= SplitState.maxPeople
              ? null
              : () => onChanged(people + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
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
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        radius: 28,
        child: SizedBox.square(
          dimension: Chrome.minTouch,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.raised,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SizedBox.square(
                dimension: 36,
                child: Icon(
                  icon,
                  size: 18,
                  color: onTap == null ? c.line : c.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemOwners extends ConsumerWidget {
  const _ItemOwners({required this.basket, required this.state});
  final Basket basket;
  final SplitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final vm = ref.read(splitProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who had what', style: t.titleMedium),
        const SizedBox(height: Space.xs),
        Text(
          'Tap names to share an item between them. With nobody picked, '
          'everyone shares it.',
          style: t.bodySmall,
        ),
        for (final item in basket.items) ...[
          const SizedBox(height: Space.sm),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: Radii.cardR,
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.quantity > 1
                            ? '${item.quantity} × ${item.name}'
                            : item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.lineTotal.format(),
                          maxLines: 1,
                          style: t.bodyMedium?.copyWith(
                            fontFeatures: DaftarType.tabular,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    _Pill(
                      label: 'Everyone',
                      semanticLabel: 'Everyone shares ${item.name}',
                      selected: (state.owners[item.id] ?? const {})
                          .where((i) => i < state.people)
                          .isEmpty,
                      onTap: () => vm.shareWithAll(item.id),
                    ),
                    for (var i = 0; i < state.people; i++)
                      _Pill(
                        label: 'P${i + 1}',
                        semanticLabel:
                            '${SplitState.personName(i)} shares ${item.name}',
                        selected: (state.owners[item.id] ?? const {}).contains(
                          i,
                        ),
                        onTap: () => vm.toggleOwner(item.id, i),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CashRounding extends StatelessWidget {
  const _CashRounding({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        borderRadius: Radii.inputR,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Chrome.minTouch),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Round to 0.050 for cash', style: t.titleSmall),
                    Text(
                      'Coins only: shares become multiples of 0.050 TND.',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemainderPicker extends StatelessWidget {
  const _RemainderPicker({required this.state, required this.onSelect});
  final SplitState state;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = SplitState.personName(state.remainderIndex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who pays the remainder', style: t.titleSmall),
        const SizedBox(height: Space.xs),
        Text(
          state.cashRounding
              ? 'Everyone else pays a multiple of 0.050. $name pays whatever '
                    'is left, so the total stays exact.'
              : 'A total that does not divide evenly leaves a few millimes. '
                    'They go one each to the first people, in order; '
                    '$name gets the first one.',
          style: t.bodySmall,
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (var i = 0; i < state.people; i++)
              _Pill(
                label: 'P${i + 1}',
                semanticLabel: '${SplitState.personName(i)} pays the remainder',
                selected: i == state.remainderIndex,
                onTap: () => onSelect(i),
              ),
          ],
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.state, required this.outcome});
  final SplitState state;
  final SplitOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final result = outcome.result;
    if (result == null) {
      return Text(outcome.hint ?? '', style: t.bodyMedium);
    }
    final equal = state.style == SplitStyle.equal;
    final remainder = state.personIds[state.remainderIndex];
    // The typical share: first person who is not the remainder person.
    final typical = result.shares.entries
        .firstWhere(
          (e) => e.key != remainder,
          orElse: () => result.shares.entries.first,
        )
        .value;
    final allEqual = result.shares.values.every((m) => m == typical);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (equal)
          Semantics(
            container: true,
            label:
                '${allEqual ? 'Each pays' : 'Most pay'} '
                '${typical.formatWithCode()}',
            excludeSemantics: true,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: c.lime,
                borderRadius: Radii.cardR,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    allEqual ? 'Each pays' : 'Most pay',
                    style: t.labelLarge?.copyWith(color: c.onLime),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _AnimatedMoney(
                      value: typical,
                      style: DaftarType.price(40, c.onLime),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Row(
            children: [
              Expanded(child: Text('Bill total', style: t.titleSmall)),
              const SizedBox(width: Space.sm),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    result.total.formatWithCode(),
                    maxLines: 1,
                    style: DaftarType.price(
                      24,
                      c.text,
                    ).copyWith(letterSpacing: 0),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: Space.md),
        for (var i = 0; i < state.people; i++)
          _ShareRow(
            name: SplitState.personName(i),
            share: result.shares[state.personIds[i]]!,
            remainder:
                i == state.remainderIndex &&
                !allEqual &&
                _isOdd(result, state, i),
          ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(child: Text('Total', style: t.bodySmall)),
            Text(
              result.sum.formatWithCode(),
              style: t.bodySmall?.copyWith(fontFeatures: DaftarType.tabular),
            ),
          ],
        ),
      ],
    );
  }

  /// True when [i]'s share differs from the typical one (so a note is useful).
  static bool _isOdd(SplitResult r, SplitState s, int i) {
    final mine = r.shares[s.personIds[i]]!;
    return r.shares.entries.any(
      (e) => e.key != s.personIds[i] && e.value != mine,
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.name,
    required this.share,
    required this.remainder,
  });
  final String name;
  final Money share;
  final bool remainder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(
        children: [
          Expanded(
            child: Text(
              remainder ? '$name · pays the remainder' : name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium,
            ),
          ),
          const SizedBox(width: Space.sm),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                share.formatWithCode(),
                maxLines: 1,
                style: DaftarType.price(16, c.text).copyWith(letterSpacing: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Motion: the share rolls to its new value; with reduced motion it just
/// shows the final number.
class _AnimatedMoney extends StatelessWidget {
  const _AnimatedMoney({required this.value, required this.style});
  final Money value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (DaftarMotion.reduced(context)) {
      return Text(value.formatWithCode(), maxLines: 1, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.minor.toDouble()),
      duration: DaftarMotion.base,
      curve: DaftarMotion.standard,
      builder: (context, v, _) => Text(
        Money(v.round(), value.currency).formatWithCode(),
        maxLines: 1,
        style: style,
      ),
    );
  }
}
