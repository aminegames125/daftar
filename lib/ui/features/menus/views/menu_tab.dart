import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../core/format/relative_date.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_long_press_menu.dart';
import '../../../core/widgets/skeleton.dart';
import '../../places/view_models/place_activity.dart';
import '../view_models/menu_view_model.dart';
import 'menu_item_editor.dart';
import 'usual_star.dart';

/// "Your usual" card: the starred items of a venue, for the top of the place page.
class UsualCard extends ConsumerWidget {
  const UsualCard({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usual =
        ref.watch(menuDataProvider(placeId)).value?.usual ??
        const <MenuItemView>[];
    if (usual.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
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
              Icon(Icons.star_rounded, size: 18, color: c.accentText),
              const SizedBox(width: Space.sm),
              Text('Your usual', style: t.titleMedium),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final item in usual) _UsualLine(item: item),
        ],
      ),
    );
  }
}

class _UsualLine extends StatelessWidget {
  const _UsualLine({required this.item});

  final MenuItemView item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final low = item.lowestPrice;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyLarge,
            ),
          ),
          if (low != null)
            PriceText(price: low, prefix: item.hasSizes ? 'from ' : null),
        ],
      ),
    );
  }
}

/// A price as `4.400` + a small muted `TND`.
class PriceText extends StatelessWidget {
  const PriceText({
    super.key,
    required this.price,
    this.prefix,
    this.size = 16,
    this.faded = false,
  });

  final Money price;
  final String? prefix;
  final double size;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Opacity(
      opacity: faded ? 0.4 : 1,
      child: Text.rich(
        TextSpan(
          children: [
            if (prefix != null) TextSpan(text: prefix, style: t.bodySmall),
            TextSpan(
              text: price.format(),
              style: DaftarType.price(size, c.text),
            ),
            TextSpan(
              text: ' ${price.currency.code}',
              style: t.bodySmall?.copyWith(fontSize: size * 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Menu / Price list tab of a venue: sections, items with sizes and prices,
/// add and edit, and "Snap a menu".
class MenuTab extends ConsumerWidget {
  const MenuTab({super.key, required this.placeId, this.label = 'Menu'});

  final String placeId;

  /// "Menu" or "Price list".
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuDataProvider(placeId));
    final staleDays = ref.watch(staleDaysProvider).value ?? 90;
    final c = context.colors;
    final lower = label.toLowerCase();

    return menu.when(
      loading: () => const SkeletonList(itemCount: 4),
      error: (_, _) => EmptyState(message: "Couldn't load the $lower."),
      data: (data) {
        final actions = Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.push('${Routes.menuSnap}?placeId=$placeId'),
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('Snap a menu'),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showMenuItemEditor(context, placeId: placeId),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add item'),
              ),
            ),
          ],
        );
        if (data.isEmpty) {
          return Column(
            children: [
              EmptyState(
                message: 'No $lower yet.\nSnap a photo of it or type it in.',
              ),
              actions,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            actions,
            for (final section in data.sections) ...[
              if (section.section != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: Space.xl,
                    bottom: Space.xs,
                  ),
                  child: _SectionHeader(
                    placeId: placeId,
                    name: section.section!.name,
                    onRename: () => _rename(context, ref, section),
                    onDelete: () => ref
                        .read(menuActionsProvider(placeId))
                        .deleteSection(section.section!.id),
                  ),
                )
              else
                const SizedBox(height: Space.md),
              for (final item in section.items)
                _ItemRow(placeId: placeId, item: item, staleDays: staleDays),
              if (section.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Text(
                    'Empty section',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: c.muted),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    MenuSectionView section,
  ) async {
    final controller = TextEditingController(text: section.section!.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename section'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await ref
          .read(menuActionsProvider(placeId))
          .renameSection(section.section!, name);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.placeId,
    required this.name,
    required this.onRename,
    required this.onDelete,
  });

  final String placeId;
  final String name;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GlassLongPressMenu(
      actions: [
        GlassMenuAction(
          icon: Icons.edit_outlined,
          label: 'Rename',
          onTap: onRename,
        ),
        GlassMenuAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete section',
          destructive: true,
          onTap: onDelete,
        ),
      ],
      child: Semantics(header: true, child: Text(name, style: t.headlineSmall)),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({
    required this.placeId,
    required this.item,
    required this.staleDays,
  });

  final String placeId;
  final MenuItemView item;
  final int staleDays;

  bool _isStale(PriceEntry? e) =>
      e != null && DateTime.now().difference(e.seenAt).inDays > staleDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final single = !item.hasSizes;
    final first = item.options.isEmpty ? null : item.options.first;

    return GlassLongPressMenu(
      onTap: () =>
          showMenuItemEditor(context, placeId: placeId, existing: item),
      actions: [
        GlassMenuAction(
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: () =>
              showMenuItemEditor(context, placeId: placeId, existing: item),
        ),
        GlassMenuAction(
          icon: item.item.isUsual
              ? Icons.star_outline_rounded
              : Icons.star_rounded,
          label: item.item.isUsual ? 'Remove from usual' : 'Mark as usual',
          onTap: () => ref
              .read(menuActionsProvider(placeId))
              .setUsual(item.item.id, isUsual: !item.item.isUsual),
        ),
        GlassMenuAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          destructive: true,
          onTap: () =>
              ref.read(menuActionsProvider(placeId)).deleteItem(item.item.id),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.item.name, style: t.titleMedium),
                    if (!single)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Wrap(
                          spacing: Space.md,
                          runSpacing: Space.xs,
                          children: [
                            for (final o in item.options)
                              Opacity(
                                opacity: _isStale(o.latest) ? 0.4 : 1,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${o.option.name ?? ''} ',
                                        style: t.bodySmall,
                                      ),
                                      TextSpan(
                                        text: o.latest?.amount.format() ?? '—',
                                        style: DaftarType.price(14, c.text),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (single && first?.latest != null)
                      Text(
                        'Seen ${formatRelativeDate(first!.latest!.seenAt)}${_isStale(first.latest) ? ' · old' : ''}',
                        style: t.bodySmall,
                      ),
                  ],
                ),
              ),
              if (single && first?.latest != null)
                PriceText(
                  price: first!.latest!.amount,
                  faded: _isStale(first.latest),
                ),
              UsualStar(
                isUsual: item.item.isUsual,
                itemName: item.item.name,
                onChanged: (v) => ref
                    .read(menuActionsProvider(placeId))
                    .setUsual(item.item.id, isUsual: v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
