import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/glass_long_press_menu.dart';
import '../../../core/widgets/skeleton.dart';
import '../../products/views/select_chip.dart';
import '../view_models/places_providers.dart';
import 'place_icons.dart';
import 'place_row.dart';

/// All places, with search and a type filter (`Routes.places`).
class PlaceListScreen extends ConsumerWidget {
  const PlaceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(placeEntriesProvider);
    final filter = ref.watch(placeListFilterProvider);
    final total = ref.watch(placesProvider).value?.length;
    final types = ref.watch(placeTypesProvider).value ?? const [];
    final isFiltering = filter.query.trim().isNotEmpty || filter.typeId != null;

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: DaftarActionBar(
        actions: const [],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Add place',
          onTap: () => context.push(Routes.placeNew),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: 'Places',
            subtitle: total == null
                ? null
                : (total == 1 ? '1 place' : '$total places'),
            expandedHeight: 120,
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: () =>
                  context.canPop() ? context.pop() : context.go(Routes.home),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Space.sm,
              ),
              child: TextField(
                textDirection: null,
                textInputAction: TextInputAction.search,
                onChanged: ref.read(placeListFilterProvider.notifier).setQuery,
                decoration: const InputDecoration(
                  hintText: 'Search your places',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
          ),
          if (types.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: Chrome.minTouch,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  itemCount: types.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
                  itemBuilder: (_, i) => SelectChip(
                    label: types[i].name,
                    icon: placeTypeIcon(types[i].iconKey),
                    selected: filter.typeId == types[i].id,
                    onTap: () => ref
                        .read(placeListFilterProvider.notifier)
                        .toggleType(types[i].id),
                  ),
                ),
              ),
            ),
          entries.when(
            loading: () => const SliverToBoxAdapter(
              child: SkeletonList(
                padding: EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                  vertical: Space.lg,
                ),
              ),
            ),
            error: (_, _) => const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(message: "Couldn't load your places."),
            ),
            data: (list) {
              if (list.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyState(
                      message: isFiltering
                          ? 'No place matches.'
                          : 'No places yet.',
                      actionLabel: isFiltering ? null : 'Add place',
                      onAction: isFiltering
                          ? null
                          : () => context.push(Routes.placeNew),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Chrome.contentBottomPadding,
                ),
                sliver: SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    return GlassLongPressMenu(
                      onTap: () => context.push(Routes.placeDetail(e.place.id)),
                      actions: [
                        GlassMenuAction(
                          icon: Icons.edit_outlined,
                          label: 'Edit',
                          onTap: () =>
                              context.push(Routes.placeEdit(e.place.id)),
                        ),
                        GlassMenuAction(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete',
                          destructive: true,
                          onTap: () => confirmDeletePlace(
                            context,
                            ref,
                            e.place.id,
                            e.place.name,
                          ),
                        ),
                      ],
                      child: PlaceRow(entry: e),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Asks, then soft-deletes the place (its prices and menu stay in the database).
Future<bool> confirmDeletePlace(
  BuildContext context,
  WidgetRef ref,
  String id,
  String name,
) async {
  final c = context.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $name?'),
      content: const Text(
        'The place disappears from your lists. Prices you logged here are kept.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Delete', style: TextStyle(color: c.coral)),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await ref.read(placeActionsProvider).delete(id);
  if (context.mounted) FloatingToast.show(context, 'Place deleted');
  return true;
}
