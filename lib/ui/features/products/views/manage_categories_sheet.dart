import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/search/normalize_for_search.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/catalog_providers.dart';
import 'category_chips.dart';

/// Icon key given to categories the user creates.
const String kCustomCategoryIcon = 'category';

/// Why [name] cannot be used for a category, or null when it is fine
/// (accent / case-insensitive duplicate check; [exceptId] is the one being renamed).
String? categoryNameError(
  String name,
  Iterable<Category> existing, {
  String? exceptId,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Give the category a name.';
  final key = normalizeForSearch(trimmed);
  for (final c in existing) {
    if (c.id != exceptId && normalizeForSearch(c.name) == key) {
      return 'That category already exists.';
    }
  }
  return null;
}

/// A new user category placed after the existing ones.
Category newCategory(String name, Iterable<Category> existing) {
  final last = existing.fold<int>(
    0,
    (m, c) => c.sortOrder > m ? c.sortOrder : m,
  );
  return Category(
    id: newId(),
    name: name.trim(),
    iconKey: kCustomCategoryIcon,
    sortOrder: last + 1,
  );
}

/// Bottom sheet to add, rename and hide categories (the starter set is editable).
Future<void> showManageCategories(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const ManageCategoriesSheet(),
  );
}

class ManageCategoriesSheet extends ConsumerWidget {
  const ManageCategoriesSheet({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<Category> all, [
    Category? category,
  ]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(existing: all, category: category),
    );
    if (name == null) return;
    final repo = ref.read(categoriesRepositoryProvider);
    await repo.save(
      category == null
          ? newCategory(name, all)
          : Category(
              id: category.id,
              name: name.trim(),
              iconKey: category.iconKey,
              sortOrder: category.sortOrder,
              isBuiltIn: category.isBuiltIn,
            ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Categories', style: t.headlineSmall),
          const SizedBox(height: Space.xs),
          Text(
            'Tap a category to rename it. Products keep their category if you hide it.',
            style: t.bodySmall?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.md),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final category in categories)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      categoryIcon(category.iconKey),
                      color: c.muted,
                    ),
                    title: Text(category.name),
                    onTap: () => _edit(context, ref, categories, category),
                    trailing: IconButton(
                      tooltip: 'Hide ${category.name}',
                      icon: Icon(Icons.delete_outline_rounded, color: c.muted),
                      onPressed: () => ref
                          .read(categoriesRepositoryProvider)
                          .delete(category.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _edit(context, ref, categories),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add category'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.existing, this.category});

  final List<Category> existing;
  final Category? category;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.category?.name ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = categoryNameError(
      _controller.text,
      widget.existing,
      exceptId: widget.category?.id,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'New category' : 'Rename category'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: 'Name', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
