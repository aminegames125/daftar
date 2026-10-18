import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/basket.dart';
import '../../../../domain/models/money.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../prices/views/widgets/place_picker_sheet.dart';
import '../view_models/calculator_providers.dart';
import 'add_item_sheet.dart';
import 'quantity_roll.dart';
import 'saved_lists_basket_menu.dart';

/// Basket mode: pick a place, add items (catalog or typed), set quantities and
/// watch the running total. The basket lives in [basketProvider] (memory only).
class BasketMode extends ConsumerWidget {
  const BasketMode({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basket = ref.watch(basketProvider);
    final vm = ref.read(basketProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              Expanded(
                child: _PlaceRow(
                  basket: basket,
                  onPick: () async {
                    final place = await showPlacePicker(context);
                    if (place != null) {
                      vm.setPlace(id: place.id, name: place.name);
                    }
                  },
                  onClear: () => vm.setPlace(),
                ),
              ),
              const SavedListsBasketMenu(),
            ],
          ),
        ),
        Expanded(
          child: basket.isEmpty
              ? const Center(
                  child: SingleChildScrollView(
                    child: EmptyState(
                      message:
                          'Your basket is empty.\nAdd what you plan to buy.',
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.sm,
                    Space.gutter,
                    Space.sm,
                  ),
                  itemCount: basket.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (context, i) {
                    final item = basket.items[i];
                    return _ItemTile(
                      key: ValueKey(item.id),
                      item: item,
                      onQuantity: (q) => vm.setQuantity(item.id, q),
                    );
                  },
                ),
        ),
        _TotalBar(
          basket: basket,
          onAdd: () => showAddItemSheet(context),
          onClear: basket.isEmpty ? null : vm.clear,
        ),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.basket,
    required this.onPick,
    required this.onClear,
  });

  final Basket basket;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final name = basket.placeName;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: name == null ? 'Choose a place' : 'Place: $name. Change',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: Radii.inputR,
              onTap: onPick,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Chrome.minTouch),
                child: Row(
                  children: [
                    Icon(Icons.place_outlined, size: 20, color: c.muted),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        name ?? 'Choose a place',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(
                          color: name == null ? c.muted : c.text,
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more_rounded, color: c.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (name != null)
          IconButton(
            tooltip: 'No place',
            onPressed: onClear,
            icon: Icon(Icons.close_rounded, color: c.muted),
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({super.key, required this.item, required this.onQuantity});

  final BasketItem item;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onQuantity(0),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.lg),
        decoration: BoxDecoration(
          color: c.coral.withValues(alpha: 0.2),
          borderRadius: Radii.cardR,
        ),
        child: Icon(Icons.delete_outline_rounded, color: c.coral),
      ),
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.cardR,
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: null,
                    style: t.titleMedium,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${item.unitPrice.format()} each',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      fontFeatures: DaftarType.tabular,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            SizedBox(
              width: _QuantityStepper.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _QuantityStepper(
                    quantity: item.quantity,
                    name: item.name,
                    onChanged: onQuantity,
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      item.lineTotal.format(),
                      maxLines: 1,
                      style: DaftarType.price(
                        16,
                        c.text,
                      ).copyWith(letterSpacing: 0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  /// Two step buttons and the rolling number.
  static const double width = Chrome.minTouch * 2 + 36;

  const _QuantityStepper({
    required this.quantity,
    required this.name,
    required this.onChanged,
  });

  final int quantity;
  final String name;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final atMin = quantity <= 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: atMin ? Icons.delete_outline_rounded : Icons.remove_rounded,
          label: atMin ? 'Remove $name' : 'One less $name',
          onTap: () => onChanged(quantity - 1),
        ),
        SizedBox(
          width: 36,
          height: Chrome.minTouch,
          child: Center(
            child: Semantics(
              label: 'Quantity $quantity',
              excludeSemantics: true,
              child: QuantityRoll(
                value: quantity,
                style: DaftarType.price(20, c.text).copyWith(letterSpacing: 0),
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          label: 'One more $name',
          onTap: quantity >= Basket.maxQuantity
              ? null
              : () => onChanged(quantity + 1),
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
      child: Squish(
        enabled: onTap != null,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
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

class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.basket,
    required this.onAdd,
    required this.onClear,
  });

  final Basket basket;
  final VoidCallback onAdd;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final units = basket.itemCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.md,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Total ${basket.total.formatWithCode()}, $units items',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    units == 1 ? 'Total · 1 item' : 'Total · $units items',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          basket.total.format(),
                          maxLines: 1,
                          style: DaftarType.price(32, c.text),
                        ),
                        const SizedBox(width: Space.xs),
                        Text(
                          Currency.tnd.code,
                          style: DaftarType.price(
                            14,
                            c.muted,
                          ).copyWith(letterSpacing: 0),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              if (onClear != null)
                IconButton(
                  tooltip: 'Empty basket',
                  onPressed: onClear,
                  icon: Icon(Icons.delete_sweep_outlined, color: c.muted),
                ),
              Expanded(
                child: SizedBox(
                  height: Chrome.minTouch,
                  child: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text(
                      'Add item',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
