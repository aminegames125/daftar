import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../prices/views/widgets/form_bits.dart';
import '../../products/view_models/catalog_providers.dart';
import '../view_models/basket_lookup.dart';
import '../view_models/saved_lists_providers.dart';

/// Asks for a list name. Resolves to the trimmed name, or null when cancelled.
Future<String?> showListNameSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ListNameSheet(
      title: title,
      confirmLabel: confirmLabel,
      initial: initial,
    ),
  );
}

class _ListNameSheet extends StatefulWidget {
  const _ListNameSheet({
    required this.title,
    required this.confirmLabel,
    required this.initial,
  });

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_ListNameSheet> createState() => _ListNameSheetState();
}

class _ListNameSheetState extends State<_ListNameSheet> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the list a name');
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
            Text(widget.title, style: t.headlineSmall),
            const SizedBox(height: Space.md),
            TextField(
              controller: _name,
              autofocus: true,
              textDirection: null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: boardInput(
                context,
                hint: 'Monthly groceries',
                errorText: _error,
              ),
            ),
            const SizedBox(height: Space.lg),
            SizedBox(
              width: double.infinity,
              height: Chrome.minTouch + Space.xs,
              child: FilledButton(
                onPressed: _submit,
                child: Text(
                  widget.confirmLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add items to a list: type a name, pick a catalog match or add it as typed.
/// Several adds in a row are fine; the sheet resets after each one.
Future<void> showAddListItemSheet(BuildContext context, String listId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AddListItemSheet(listId: listId),
  );
}

class AddListItemSheet extends ConsumerStatefulWidget {
  const AddListItemSheet({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<AddListItemSheet> createState() => _AddListItemSheetState();
}

class _AddListItemSheetState extends ConsumerState<AddListItemSheet> {
  final _name = TextEditingController();
  BasketCandidate? _picked;
  String? _error;
  int _added = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _name.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    final variantId = _picked?.variant.id;
    await ref
        .read(savedListsActionsProvider)
        .addItem(
          widget.listId,
          variantId: (variantId == null || variantId.isEmpty)
              ? null
              : variantId,
          freeText: text,
        );
    if (!mounted) return;
    setState(() {
      _name.clear();
      _picked = null;
      _error = null;
      _added++;
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
            TextField(
              controller: _name,
              textDirection: null,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {
                _picked = null;
                _error = null;
              }),
              onSubmitted: (_) => unawaited(_add()),
              decoration: boardInput(
                context,
                hint: 'Milk, bread, or search your products',
                errorText: _error,
              ),
            ),
            for (final s in suggestions)
              Semantics(
                button: true,
                label: 'Use ${s.label}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: Radii.inputR,
                  onTap: () => setState(() {
                    _picked = s;
                    _name.text = s.label;
                    _error = null;
                  }),
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
            const SizedBox(height: Space.lg),
            SizedBox(
              width: double.infinity,
              height: Chrome.minTouch + Space.xs,
              child: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Add to list',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_added > 0)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Done · $_added added'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
