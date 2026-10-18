import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/daftar_tokens.dart';
import '../view_models/catalog_providers.dart';
import 'select_chip.dart';

/// Resolves a category `iconKey` (seeded in the database) to an icon.
IconData categoryIcon(String key) => switch (key) {
  'restaurant' => Icons.restaurant_rounded,
  'local_drink' => Icons.local_drink_outlined,
  'cookie' => Icons.cookie_outlined,
  'egg' => Icons.egg_alt_outlined,
  'cleaning' => Icons.cleaning_services_outlined,
  'hygiene' => Icons.soap_outlined,
  'baby' => Icons.child_care_rounded,
  'devices' => Icons.devices_other_outlined,
  'checkroom' => Icons.checkroom_rounded,
  'build' => Icons.build_outlined,
  'directions_car' => Icons.directions_car_outlined,
  _ => Icons.category_outlined,
};

/// A wrapping row of category chips (the starter set from the database).
///
/// With [showAll] an "All" chip clears the selection (used as a filter); without
/// it, tapping the selected chip again clears it (used to pick a category).
class CategoryChips extends ConsumerWidget {
  const CategoryChips({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.showAll = false,
  });

  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final bool showAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    return Wrap(
      spacing: Space.sm,
      children: [
        if (showAll)
          SelectChip(
            label: 'All',
            selected: selectedId == null,
            onTap: () => onSelected(null),
          ),
        for (final category in categories)
          SelectChip(
            label: category.name,
            icon: categoryIcon(category.iconKey),
            selected: selectedId == category.id,
            onTap: () => onSelected(
              selectedId == category.id && !showAll ? null : category.id,
            ),
          ),
      ],
    );
  }
}
