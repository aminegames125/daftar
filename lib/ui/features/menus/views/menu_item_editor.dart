import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/money.dart';
import '../../../core/motion/shake.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/money_field.dart';
import '../../products/views/select_chip.dart';
import '../view_models/menu_view_model.dart';
import 'usual_star.dart';

/// Opens the add / edit sheet for one menu item. Returns true when something was saved or deleted.
Future<bool> showMenuItemEditor(
  BuildContext context, {
  required String placeId,
  MenuItemView? existing,
  String? sectionId,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _MenuItemEditor(
      placeId: placeId,
      existing: existing,
      initialSectionId: sectionId,
    ),
  );
  return changed ?? false;
}

class _OptionRow {
  _OptionRow({this.id, String name = '', this.price})
    : name = TextEditingController(text: name);

  final String? id;
  final TextEditingController name;
  Money? price;
}

class _MenuItemEditor extends ConsumerStatefulWidget {
  const _MenuItemEditor({
    required this.placeId,
    this.existing,
    this.initialSectionId,
  });

  final String placeId;
  final MenuItemView? existing;
  final String? initialSectionId;

  @override
  ConsumerState<_MenuItemEditor> createState() => _MenuItemEditorState();
}

class _MenuItemEditorState extends ConsumerState<_MenuItemEditor> {
  late final _name = TextEditingController(
    text: widget.existing?.item.name ?? '',
  );
  late String? _sectionId =
      widget.existing?.item.sectionId ?? widget.initialSectionId;
  late bool _usual = widget.existing?.item.isUsual ?? false;
  late final List<_OptionRow> _options;
  var _showErrors = false;
  var _shake = 0;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _options = existing == null || existing.options.isEmpty
        ? [_OptionRow()]
        : [
            for (final o in existing.options)
              _OptionRow(
                id: o.option.id,
                name: o.option.name ?? '',
                price: o.latest?.amount,
              ),
          ];
  }

  @override
  void dispose() {
    _name.dispose();
    for (final o in _options) {
      o.name.dispose();
    }
    super.dispose();
  }

  MenuActions get _actions => ref.read(menuActionsProvider(widget.placeId));

  bool get _hasSizes => _options.length > 1;

  void _addSize() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_options.length == 1) {
        // The first price becomes "S"; the user can rename both.
        if (_options.first.name.text.trim().isEmpty) {
          _options.first.name.text = 'S';
        }
        _options.add(_OptionRow(name: 'L'));
      } else {
        _options.add(_OptionRow());
      }
    });
  }

  void _removeSize(int index) {
    setState(() {
      _options.removeAt(index).name.dispose();
      if (_options.length == 1) _options.first.name.clear();
    });
  }

  Future<void> _addSection() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New section'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Hot drinks'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final id = await _actions.addSection(name);
    if (mounted) setState(() => _sectionId = id);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() {
        _showErrors = true;
        _shake++;
      });
      unawaited(HapticFeedback.mediumImpact());
      return;
    }
    setState(() => _saving = true);
    await _actions.saveItem(
      itemId: widget.existing?.item.id,
      name: _name.text,
      sectionId: _sectionId,
      isUsual: _usual,
      options: [
        for (final o in _options)
          OptionInput(id: o.id, name: o.name.text, price: o.price),
      ],
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.existing!.item.name}?'),
        content: const Text('Its price history is kept.'),
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
    if (ok != true) return;
    await _actions.deleteItem(widget.existing!.item.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final sections =
        ref.watch(menuSectionsProvider(widget.placeId)).value ?? const [];
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEdit ? 'Edit item' : 'New item',
                    style: t.headlineSmall,
                  ),
                ),
                UsualStar(
                  isUsual: _usual,
                  itemName: _name.text.trim().isEmpty
                      ? null
                      : _name.text.trim(),
                  onChanged: (v) => setState(() => _usual = v),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Shake(
              trigger: _shake,
              child: TextField(
                controller: _name,
                autofocus: !isEdit,
                textDirection: null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: _showErrors && _name.text.trim().isEmpty
                      ? 'Give the item a name'
                      : null,
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text('Section', style: t.bodySmall),
            Wrap(
              spacing: Space.sm,
              children: [
                SelectChip(
                  label: 'None',
                  selected: _sectionId == null,
                  onTap: () => setState(() => _sectionId = null),
                ),
                for (final s in sections)
                  SelectChip(
                    label: s.name,
                    selected: _sectionId == s.id,
                    onTap: () => setState(() => _sectionId = s.id),
                  ),
                SelectChip(
                  label: '+ Section',
                  selected: false,
                  isAdd: true,
                  onTap: _addSection,
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Text(_hasSizes ? 'Sizes and prices' : 'Price', style: t.bodySmall),
            const SizedBox(height: Space.sm),
            for (var i = 0; i < _options.length; i++)
              Padding(
                key: ObjectKey(_options[i]),
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.sm,
                  ),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: Radii.inputR,
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    children: [
                      if (_hasSizes) ...[
                        SizedBox(
                          width: 72,
                          child: TextField(
                            controller: _options[i].name,
                            textDirection: null,
                            decoration: const InputDecoration(
                              hintText: 'Size',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.md),
                      ],
                      Expanded(
                        child: MoneyField(
                          initialValue: _options[i].price,
                          fontSize: 24,
                          semanticLabel: _hasSizes
                              ? 'Price of size ${i + 1}'
                              : 'Price',
                          onChanged: (m) => _options[i].price = m,
                        ),
                      ),
                      if (_hasSizes)
                        IconButton(
                          tooltip: 'Remove size',
                          onPressed: () => _removeSize(i),
                          icon: Icon(Icons.close_rounded, color: c.muted),
                        ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addSize,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  _hasSizes ? 'Add another size' : 'Add a size (S / L)',
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(isEdit ? 'Save item' : 'Add item'),
            ),
            if (isEdit)
              TextButton(
                onPressed: _delete,
                child: Text('Delete item', style: TextStyle(color: c.coral)),
              ),
          ],
        ),
      ),
    );
  }
}
