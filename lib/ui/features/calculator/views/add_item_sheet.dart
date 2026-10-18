import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/money_field.dart';
import '../../prices/views/widgets/form_bits.dart';
import '../../products/view_models/catalog_providers.dart';
import '../view_models/basket_lookup.dart';
import '../view_models/calculator_providers.dart';

/// Bottom sheet: type a name (catalog matches appear and prefill the price) and a
/// price, then add the line to the basket. Several adds in a row are fine: the
/// sheet resets after each one and closes with the handle or back.
Future<void> showAddItemSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const AddItemSheet(),
  );
}

class AddItemSheet extends ConsumerStatefulWidget {
  const AddItemSheet({super.key});

  @override
  ConsumerState<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<AddItemSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  Money? _amount;
  BasketCandidate? _picked;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pick(BasketCandidate candidate) async {
    setState(() {
      _picked = candidate;
      _name.text = candidate.label;
      _error = null;
    });
    final id = candidate.variant.id;
    if (id.isEmpty) return;
    final offers = await ref
        .read(pricesRepositoryProvider)
        .currentOffersForVariant(id);
    if (!mounted || _picked != candidate) return;
    final placeId = ref.read(basketProvider).placeId;
    final price = suggestedPrice(offers, placeId);
    if (price != null) {
      setState(() {
        _amount = price;
        _price.text = moneyInputText(price);
      });
    }
  }

  void _add() {
    final name = _name.text.trim();
    final amount = _amount;
    if (name.isEmpty || amount == null) {
      setState(() => _error = name.isEmpty ? 'Give it a name' : 'Add a price');
      return;
    }
    HapticFeedback.mediumImpact();
    final picked = _picked;
    ref
        .read(basketProvider.notifier)
        .add(
          name: name,
          unitPrice: amount,
          productId: picked?.product.id,
          variantId: (picked?.variant.id.isEmpty ?? true)
              ? null
              : picked!.variant.id,
        );
    setState(() {
      _name.clear();
      _price.clear();
      _amount = null;
      _picked = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final products = ref.watch(productsProvider).value ?? const [];
    final suggestions = _picked == null
        ? searchCandidates(products, _name.text)
        : const <BasketCandidate>[];
    final inBasket = ref.watch(basketProvider.select((b) => b.lineCount));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add an item', style: t.headlineSmall),
            const SizedBox(height: Space.md),
            const FieldLabel('Name'),
            const SizedBox(height: Space.xs),
            TextField(
              controller: _name,
              textDirection: null,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {
                _picked = null;
                _error = null;
              }),
              decoration: boardInput(
                context,
                hint: 'Milk, bread, or search your products',
              ),
            ),
            for (final s in suggestions)
              Semantics(
                button: true,
                label: 'Use ${s.label}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: Radii.inputR,
                  onTap: () => _pick(s),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: Chrome.minTouch,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: c.muted,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: Space.md),
            MoneyField(
              controller: _price,
              label: 'Price each',
              fontSize: 32,
              onChanged: (m) => setState(() {
                _amount = m;
                _error = null;
              }),
              errorText: _error,
            ),
            const SizedBox(height: Space.lg),
            SizedBox(
              width: double.infinity,
              height: Chrome.minTouch + Space.xs,
              child: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add to basket'),
              ),
            ),
            if (inBasket > 0)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Done · $inBasket in basket'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
