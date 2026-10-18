import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/basket.dart';
import '../../../../domain/models/saved_list.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/hold_to_confirm.dart';
import '../../../core/widgets/success_check.dart';
import '../view_models/saved_lists_pricing.dart';
import '../view_models/saved_lists_providers.dart';
import 'saved_lists_sheets.dart';
import 'saved_lists_widgets.dart';

enum _Menu { rename, uncheckAll, delete }

/// One saved list: items to check off, reorder, remove, plus its best store and
/// total. "Use as basket" loads it into the Calculator.
class SavedListDetailScreen extends ConsumerStatefulWidget {
  const SavedListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<SavedListDetailScreen> createState() =>
      _SavedListDetailScreenState();
}

class _SavedListDetailScreenState extends ConsumerState<SavedListDetailScreen> {
  /// Items swiped away, hidden at once while the database catches up.
  final Set<String> _removed = {};

  /// Order after a drag, shown until the database reports the same order.
  List<String>? _pendingOrder;

  SavedListsActions get _actions => ref.read(savedListsActionsProvider);

  List<SavedListItem> _visible(List<SavedListItem> items) {
    var out = [
      for (final i in items)
        if (!_removed.contains(i.id)) i,
    ];
    final pending = _pendingOrder;
    if (pending != null) {
      final same =
          out.length == pending.length &&
          [for (final i in out) i.id].toString() == pending.toString();
      if (!same) {
        final rank = {for (final (i, id) in pending.indexed) id: i};
        out = [...out]
          ..sort(
            (a, b) => (rank[a.id] ?? 1 << 20).compareTo(rank[b.id] ?? 1 << 20),
          );
      }
    }
    return out;
  }

  void _onReorder(List<SavedListItem> items, int oldIndex, int newIndex) {
    final ids = [for (final i in items) i.id];
    ids.insert(newIndex, ids.removeAt(oldIndex));
    setState(() => _pendingOrder = ids);
    HapticFeedback.selectionClick();
    unawaited(_actions.reorder(widget.listId, ids));
  }

  Future<void> _rename(SavedList list) async {
    final name = await showListNameSheet(
      context,
      title: 'Rename list',
      confirmLabel: 'Save',
      initial: list.name,
    );
    if (name != null) await _actions.rename(list, name);
  }

  Future<void> _delete(SavedList list) async {
    final ok = await showHoldToConfirm(
      context,
      title: 'Delete "${list.name}"?',
      message: 'The list and its items will be removed.',
      label: 'Hold to delete',
    );
    if (!ok) return;
    await _actions.deleteList(list.id);
    if (mounted) context.pop();
  }

  Future<void> _useAsBasket() async {
    unawaited(HapticFeedback.mediumImpact());
    await _actions.useAsBasket(widget.listId);
    if (mounted) context.go(Routes.calculator);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final list = ref.watch(savedListByIdProvider(widget.listId));
    final asyncItems = ref.watch(savedListItemsProvider(widget.listId));
    final items = _visible(asyncItems.value ?? const []);
    final summary =
        ref.watch(savedListSummaryProvider(widget.listId)).value ??
        SavedListSummary.empty;
    final checked = items.where((i) => i.isChecked).length;
    final labels = ref.watch(variantLabelsProvider);

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.add_rounded,
            label: 'Add item',
            onTap: () => showAddListItemSheet(context, widget.listId),
          ),
          ToolbarAction(
            icon: Icons.restart_alt_rounded,
            label: 'Uncheck all',
            onTap: checked == 0
                ? null
                : () => _actions.uncheckAll(widget.listId),
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.shopping_basket_outlined,
          label: 'Use as basket',
          onTap: items.isEmpty ? null : _useAsBasket,
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
                Space.sm,
                Space.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  Expanded(
                    child: Text(
                      list?.name ?? '',
                      style: t.headlineMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: null,
                    ),
                  ),
                  if (list != null)
                    PopupMenuButton<_Menu>(
                      tooltip: 'List options',
                      icon: Icon(Icons.more_vert_rounded, color: c.text),
                      onSelected: (m) => switch (m) {
                        _Menu.rename => _rename(list),
                        _Menu.uncheckAll => _actions.uncheckAll(list.id),
                        _Menu.delete => _delete(list),
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _Menu.rename,
                          child: Text('Rename'),
                        ),
                        PopupMenuItem(
                          value: _Menu.uncheckAll,
                          child: Text('Uncheck all'),
                        ),
                        PopupMenuItem(
                          value: _Menu.delete,
                          child: Text('Delete list'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? (asyncItems.isLoading
                        ? const SizedBox.shrink()
                        : Center(
                            child: SingleChildScrollView(
                              child: EmptyState(
                                message:
                                    'This list is empty.\nAdd what you buy.',
                                actionLabel: 'Add item',
                                onAction: () => showAddListItemSheet(
                                  context,
                                  widget.listId,
                                ),
                              ),
                            ),
                          ))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.sm,
                        Space.gutter,
                        Chrome.contentBottomPadding,
                      ),
                      header: Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: _SummaryCard(
                          checked: checked,
                          count: items.length,
                          summary: summary,
                        ),
                      ),
                      itemCount: items.length,
                      onReorderItem: (a, b) => _onReorder(items, a, b),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final label =
                            item.freeText ?? labels[item.variantId] ?? 'Item';
                        return Padding(
                          key: ValueKey(item.id),
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: Dismissible(
                            key: ValueKey('dismiss-${item.id}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              setState(() => _removed.add(item.id));
                              _actions.removeItem(item.id);
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: Space.lg),
                              decoration: BoxDecoration(
                                color: c.coral.withValues(alpha: 0.2),
                                borderRadius: Radii.cardR,
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: c.coral,
                              ),
                            ),
                            child: _ItemTile(
                              item: item,
                              label: label,
                              index: i,
                              onChecked: (v) {
                                HapticFeedback.selectionClick();
                                _actions.setChecked(item.id, v);
                              },
                              onQuantity: (q) {
                                if (q <= 0) {
                                  setState(() => _removed.add(item.id));
                                }
                                _actions.setQuantity(item, q);
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.checked,
    required this.count,
    required this.summary,
  });

  final int checked;
  final int count;
  final SavedListSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final done = count > 0 && checked == count;
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
              Expanded(
                child: Text(progressText(checked, count), style: t.titleMedium),
              ),
              if (done) SuccessCheck(size: 28, color: c.text),
            ],
          ),
          const SizedBox(height: Space.sm),
          SavedListProgressBar(value: count == 0 ? 0 : checked / count),
          if (count > 0) ...[
            const SizedBox(height: Space.md),
            SavedListPriceLine(summary: summary),
          ],
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.label,
    required this.index,
    required this.onChecked,
    required this.onQuantity,
  });

  final SavedListItem item;
  final String label;
  final int index;
  final ValueChanged<bool> onChecked;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final reduced = DaftarMotion.reduced(context);
    final done = item.isChecked;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            checked: done,
            label: done ? 'Uncheck $label' : 'Check off $label',
            excludeSemantics: true,
            onTap: () => onChecked(!done),
            child: InkResponse(
              onTap: () => onChecked(!done),
              radius: Chrome.minTouch / 2,
              child: SizedBox.square(
                dimension: Chrome.minTouch + Space.sm,
                child: Center(child: _CheckCircle(checked: done)),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: reduced ? Duration.zero : DaftarMotion.base,
                    curve: DaftarMotion.standard,
                    style: t.titleMedium!.copyWith(
                      color: done ? c.muted : c.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: c.muted,
                    ),
                    child: Text(
                      label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textDirection: null,
                    ),
                  ),
                  _Stepper(
                    quantity: item.quantity,
                    label: label,
                    onChanged: onQuantity,
                  ),
                ],
              ),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: 'Drag to reorder $label',
              child: SizedBox.square(
                dimension: Chrome.minTouch,
                child: Icon(Icons.drag_handle_rounded, color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The satisfying check: the ring fills and the tick pops in on a spring
/// (shown at once with "Remove animations").
class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked});

  static const double size = 28;
  static final SpringCurve _spring = SpringCurve(DaftarMotion.bouncy);

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduced = DaftarMotion.reduced(context);
    final d = reduced ? Duration.zero : DaftarMotion.base;
    return AnimatedContainer(
      duration: d,
      curve: DaftarMotion.standard,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? c.text : Colors.transparent,
        border: Border.all(color: checked ? c.text : c.muted, width: 2),
      ),
      child: AnimatedScale(
        scale: checked ? 1 : 0,
        duration: d,
        curve: _spring,
        child: Icon(Icons.check_rounded, size: 18, color: c.background),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.label,
    required this.onChanged,
  });

  final int quantity;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: quantity <= 1 ? 'Remove $label' : 'One less $label',
          constraints: const BoxConstraints.tightFor(
            width: Chrome.minTouch,
            height: Chrome.minTouch,
          ),
          onPressed: () => onChanged(quantity - 1),
          icon: Icon(
            quantity <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            size: 20,
            color: c.muted,
          ),
        ),
        Semantics(
          label: 'Quantity $quantity',
          excludeSemantics: true,
          child: Text('×$quantity', style: t.titleMedium),
        ),
        IconButton(
          tooltip: 'One more $label',
          constraints: const BoxConstraints.tightFor(
            width: Chrome.minTouch,
            height: Chrome.minTouch,
          ),
          onPressed: quantity >= Basket.maxQuantity
              ? null
              : () => onChanged(quantity + 1),
          icon: Icon(Icons.add_rounded, size: 20, color: c.muted),
        ),
      ],
    );
  }
}
