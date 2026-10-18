import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/widgets/floating_toast.dart';
import '../view_models/calculator_providers.dart';
import '../view_models/saved_lists_providers.dart';
import 'saved_lists_sheets.dart';

enum _BasketListAction { save, load }

/// Basket mode's "Lists" menu: save the basket as a list, or load a list.
class SavedListsBasketMenu extends ConsumerWidget {
  const SavedListsBasketMenu({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final name = await showListNameSheet(
      context,
      title: 'Save basket as list',
      confirmLabel: 'Save list',
      initial: 'Basket',
    );
    if (name == null) return;
    final id = await ref
        .read(savedListsActionsProvider)
        .saveBasket(name, ref.read(basketProvider));
    if (!context.mounted) return;
    FloatingToast.show(
      context,
      'Saved as "$name"',
      actionLabel: 'Open',
      onAction: () => context.push(Routes.listDetail(id)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasItems = ref.watch(basketProvider.select((b) => b.isNotEmpty));
    return PopupMenuButton<_BasketListAction>(
      tooltip: 'Lists',
      icon: Icon(Icons.checklist_rounded, color: context.colors.muted),
      onSelected: (a) => switch (a) {
        _BasketListAction.save => _save(context, ref),
        _BasketListAction.load => context.push(Routes.lists),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _BasketListAction.save,
          enabled: hasItems,
          child: const Text('Save as list'),
        ),
        const PopupMenuItem(
          value: _BasketListAction.load,
          child: Text('Load list'),
        ),
      ],
    );
  }
}
