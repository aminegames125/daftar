import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/saved_list.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../view_models/saved_lists_pricing.dart';
import '../view_models/saved_lists_providers.dart';
import 'saved_lists_sheets.dart';
import 'saved_lists_widgets.dart';

/// "Lists": every saved shopping list with its progress, best store and total.
class SavedListsScreen extends ConsumerWidget {
  const SavedListsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showListNameSheet(
      context,
      title: 'New list',
      confirmLabel: 'Create list',
    );
    if (name == null || !context.mounted) return;
    final id = await ref.read(savedListsActionsProvider).createList(name);
    if (context.mounted) unawaited(context.push(Routes.listDetail(id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final lists = ref.watch(savedListsProvider).value;
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: DaftarActionBar(
        actions: const [],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'New list',
          onTap: () => _create(context, ref),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.sm,
                Space.sm,
                Space.gutter,
                Space.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.pop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: context.colors.text,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Lists',
                      style: t.headlineLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: lists == null
                  ? const SizedBox.shrink()
                  : lists.isEmpty
                  ? const Center(
                      child: SingleChildScrollView(
                        child: EmptyState(
                          message:
                              'No lists yet.\nSave what you buy every month.',
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.sm,
                        Space.gutter,
                        Chrome.contentBottomPadding,
                      ),
                      itemCount: lists.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) =>
                          _ListCard(key: ValueKey(lists[i].id), list: lists[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListCard extends ConsumerWidget {
  const _ListCard({super.key, required this.list});

  final SavedList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final summary =
        ref.watch(savedListSummaryProvider(list.id)).value ??
        SavedListSummary.empty;
    return Semantics(
      button: true,
      label:
          '${list.name}, ${progressText(summary.checkedCount, summary.itemCount)}',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardR,
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: Radii.cardR,
          onTap: () => context.push(Routes.listDetail(list.id)),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: null,
                  style: t.titleMedium,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  progressText(summary.checkedCount, summary.itemCount),
                  style: t.bodySmall?.copyWith(color: c.muted),
                ),
                if (summary.itemCount > 0) ...[
                  const SizedBox(height: Space.sm),
                  SavedListProgressBar(value: summary.progress),
                  const SizedBox(height: Space.md),
                  SavedListPriceLine(summary: summary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
