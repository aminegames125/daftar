import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/lookups.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/hold_to_confirm.dart';
import '../../../core/widgets/skeleton.dart';
import '../view_models/managed_lists.dart';
import 'list_icons.dart';

/// Add, rename, reorder and hide the rows of one editable list. Starter rows can be
/// renamed or hidden (never destroyed) and brought back with "Restore starters".
class ManageListScreen extends ConsumerStatefulWidget {
  const ManageListScreen({super.key, required this.kind});

  final ManagedListKind kind;

  @override
  ConsumerState<ManageListScreen> createState() => _ManageListScreenState();
}

class _ManageListScreenState extends ConsumerState<ManageListScreen> {
  /// Order while a drag is being saved, so the row does not jump back.
  List<ManagedItem>? _optimistic;

  ManagedList get _list => ref.read(managedListProvider(widget.kind));

  Future<void> _add() async {
    final result = await showNameSheet(
      context,
      title: widget.kind.addLabel,
      initial: '',
      showPlaceKind: widget.kind == ManagedListKind.placeTypes,
    );
    if (result == null) return;
    await _list.add(result.name, placeKind: result.placeKind);
  }

  Future<void> _rename(ManagedItem item) async {
    final result = await showNameSheet(
      context,
      title: 'Rename',
      initial: item.name,
    );
    if (result == null || result.name == item.name) return;
    await _list.rename(item, result.name);
  }

  Future<void> _hide(ManagedItem item) async {
    final confirmed = await showHoldToConfirm(
      context,
      title: 'Hide "${item.name}"?',
      message: item.isBuiltIn
          ? 'It will disappear from the pickers. Anything that already uses it keeps working, and "Restore starters" brings it back.'
          : 'It will disappear from the pickers. Anything that already uses it keeps working.',
      label: 'Hold to hide',
    );
    if (!confirmed || !mounted) return;
    await _list.hide(item);
  }

  Future<void> _restore(List<ManagedItem> current) async {
    final count = await _list.restoreStarters(current);
    if (!mounted) return;
    FloatingToast.show(
      context,
      count == 0
          ? 'Nothing to restore'
          : (count == 1 ? 'Restored 1 starter' : 'Restored $count starters'),
      kind: count == 0 ? ToastKind.info : ToastKind.success,
    );
  }

  Future<void> _reorder(
    List<ManagedItem> items,
    int oldIndex,
    int newIndex,
  ) async {
    final next = [...items];
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() => _optimistic = next);
    await _list.reorder(next);
    if (mounted) setState(() => _optimistic = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = ref.watch(managedItemsProvider(widget.kind));
    final shown = _optimistic ?? items.value ?? const <ManagedItem>[];

    return Scaffold(
      extendBody: true,
      backgroundColor: c.background,
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.restore_rounded,
            label: 'Restore starters',
            onTap: () => _restore(shown),
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Add',
          onTap: _add,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: widget.kind.title,
            subtitle: 'Hold a row to move it · tap to rename',
            expandedHeight: 120,
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: () => context.pop(),
            ),
          ),
          if (items.isLoading && _optimistic == null)
            const SliverToBoxAdapter(
              child: SkeletonList(
                itemCount: 6,
                padding: EdgeInsets.all(Space.gutter),
              ),
            )
          else if (shown.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: EmptyState(
                  message: 'Everything here is hidden.',
                  actionLabel: 'Restore starters',
                  onAction: () => _restore(shown),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Chrome.contentBottomPadding,
              ),
              sliver: SliverReorderableList(
                itemCount: shown.length,
                onReorderItem: (a, b) => _reorder(shown, a, b),
                itemBuilder: (context, i) {
                  final item = shown[i];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(item.id),
                    index: i,
                    child: _ManagedRow(
                      item: item,
                      onRename: () => _rename(item),
                      onHide: () => _hide(item),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ManagedRow extends StatelessWidget {
  const _ManagedRow({
    required this.item,
    required this.onRename,
    required this.onHide,
  });

  final ManagedItem item;
  final VoidCallback onRename;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${item.name}${item.isBuiltIn ? ', starter' : ''}. Tap to rename',
      excludeSemantics: true,
      onTap: onRename,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Hide'): onHide,
      },
      child: Squish(
        onTap: onRename,
        pressedScale: 0.99,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          margin: const EdgeInsets.only(bottom: Space.sm),
          padding: const EdgeInsets.only(left: Space.lg),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.cardR,
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(iconForKey(item.iconKey), size: 18, color: c.muted),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: t.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.detail != null || item.isBuiltIn)
                        Text(
                          [
                            if (item.isBuiltIn) 'Starter',
                            ?item.detail,
                          ].join(' · '),
                          style: t.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
              Tooltip(
                message: 'Hide ${item.name}',
                child: Semantics(
                  button: true,
                  label: 'Hide ${item.name}',
                  excludeSemantics: true,
                  onTap: onHide,
                  child: Squish(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onHide();
                    },
                    child: SizedBox.square(
                      dimension: Chrome.minTouch,
                      child: Icon(
                        Icons.visibility_off_outlined,
                        size: 20,
                        color: c.muted,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: Space.md),
                child: Icon(Icons.drag_indicator_rounded, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the user typed in [showNameSheet].
typedef NameResult = ({String name, PlaceKind placeKind});

/// Bottom sheet with a single text field (Arabic-capable) and, for place types, a
/// Shop / Venue choice. Returns null when dismissed or empty.
Future<NameResult?> showNameSheet(
  BuildContext context, {
  required String title,
  required String initial,
  bool showPlaceKind = false,
}) {
  return showModalBottomSheet<NameResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _NameSheet(
      title: title,
      initial: initial,
      showPlaceKind: showPlaceKind,
    ),
  );
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({
    required this.title,
    required this.initial,
    required this.showPlaceKind,
  });

  final String title;
  final String initial;
  final bool showPlaceKind;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  PlaceKind _kind = PlaceKind.shop;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name: name, placeKind: _kind));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        0,
        Space.xl,
        Space.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: t.headlineSmall),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              textDirection: null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(hintText: 'Name'),
            ),
            if (widget.showPlaceKind) ...[
              const SizedBox(height: Space.lg),
              Text('This place has', style: t.bodySmall),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  for (final (kind, label) in const [
                    (PlaceKind.shop, 'Products (shop)'),
                    (PlaceKind.venue, 'A menu (venue)'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: kind == PlaceKind.shop ? Space.sm : 0,
                        ),
                        child: Squish(
                          onTap: () => setState(() => _kind = kind),
                          child: Container(
                            height: Chrome.minTouch,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _kind == kind
                                  ? c.lime.withValues(alpha: 0.12)
                                  : c.raised,
                              borderRadius: Radii.inputR,
                              border: Border.all(
                                color: _kind == kind ? c.accentText : c.line,
                              ),
                            ),
                            child: Text(
                              label,
                              style: t.labelMedium?.copyWith(
                                color: _kind == kind ? c.accentText : c.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Space.xl),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
