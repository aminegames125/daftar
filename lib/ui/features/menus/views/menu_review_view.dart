import 'package:flutter/material.dart';

import '../../../../domain/menu_logic/menu_line_parser.dart';
import '../../../../domain/menu_logic/menu_review_draft.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import 'usual_star.dart';

/// The "hard to read" hint: shown when the scan is unreliable (low confidence,
/// Arabic, blur, or few lines understood).
class HardToReadBanner extends StatelessWidget {
  const HardToReadBanner({
    super.key,
    required this.onRetake,
    required this.onTypeIt,
  });

  final VoidCallback onRetake;
  final VoidCallback onTypeIt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.amber.withValues(alpha: 0.12),
        borderRadius: Radii.cardR,
        border: Border.all(color: c.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: c.amber),
              const SizedBox(width: Space.md),
              Expanded(child: Text(menuHardToReadMessage, style: t.bodyMedium)),
            ],
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            children: [
              TextButton(
                onPressed: onRetake,
                child: const Text('Retake photo'),
              ),
              TextButton(
                onPressed: onTypeIt,
                child: const Text('Type it myself'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edit what was read before saving: sections, items, sizes and prices.
/// Every change goes through [onEdit] so the view-model owns the draft.
class MenuReviewView extends StatelessWidget {
  const MenuReviewView({super.key, required this.draft, required this.onEdit});

  final MenuReviewDraft draft;
  final void Function(MenuReviewDraft Function(MenuReviewDraft)) onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in draft.sections)
          Padding(
            key: ValueKey(section.id),
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: Radii.cardR,
                border: Border.all(color: c.line),
              ),
              child: _SectionCard(section: section, onEdit: onEdit),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => onEdit((d) {
            final withSection = d.addSection();
            return withSection.addItem(withSection.sections.last.id);
          }),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add a section'),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.onEdit});

  final ReviewSection section;
  final void Function(MenuReviewDraft Function(MenuReviewDraft)) onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: section.name,
                textDirection: null,
                textCapitalization: TextCapitalization.sentences,
                style: Theme.of(context).textTheme.titleMedium,
                onChanged: (v) => onEdit((d) => d.renameSection(section.id, v)),
                decoration: const InputDecoration(
                  labelText: 'Section (optional)',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Remove section',
              onPressed: () => onEdit((d) => d.removeSection(section.id)),
              icon: Icon(Icons.delete_outline_rounded, color: c.muted),
            ),
          ],
        ),
        for (final item in section.items) ...[
          const SizedBox(height: Space.lg),
          _ItemEditor(key: ValueKey(item.id), item: item, onEdit: onEdit),
        ],
        const SizedBox(height: Space.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => onEdit((d) => d.addItem(section.id)),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add item'),
          ),
        ),
      ],
    );
  }
}

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({super.key, required this.item, required this.onEdit});

  final ReviewItem item;
  final void Function(MenuReviewDraft Function(MenuReviewDraft)) onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sized = item.options.length > 1;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: c.raised, borderRadius: Radii.inputR),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.name,
                  textDirection: null,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (v) => onEdit((d) => d.renameItem(item.id, v)),
                  decoration: InputDecoration(
                    hintText: 'Item name',
                    fillColor: c.surface,
                  ),
                ),
              ),
              UsualStar(
                isUsual: item.isUsual,
                itemName: item.name.trim().isEmpty ? null : item.name.trim(),
                onChanged: (_) => onEdit((d) => d.toggleUsual(item.id)),
              ),
              IconButton(
                tooltip: 'Remove item',
                onPressed: () => onEdit((d) => d.removeItem(item.id)),
                icon: Icon(Icons.close_rounded, color: c.muted),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final option in item.options)
            Padding(
              key: ValueKey(option.id),
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                children: [
                  if (sized) ...[
                    SizedBox(
                      width: 84,
                      child: TextFormField(
                        initialValue: option.name,
                        textDirection: null,
                        onChanged: (v) => onEdit(
                          (d) => d.setOption(item.id, option.id, name: v),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Size',
                          fillColor: c.surface,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                  ],
                  Expanded(
                    child: TextFormField(
                      initialValue: option.price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (v) => onEdit(
                        (d) => d.setOption(item.id, option.id, price: v),
                      ),
                      decoration: InputDecoration(
                        hintText: '0.000',
                        suffixText: 'TND',
                        fillColor: c.surface,
                        enabledBorder: option.hasInvalidPrice
                            ? OutlineInputBorder(
                                borderRadius: Radii.inputR,
                                borderSide: BorderSide(color: c.coral),
                              )
                            : null,
                        errorText: option.hasInvalidPrice
                            ? 'Not a price'
                            : null,
                      ),
                    ),
                  ),
                  if (sized)
                    IconButton(
                      tooltip: 'Remove size',
                      onPressed: () =>
                          onEdit((d) => d.removeOption(item.id, option.id)),
                      icon: Icon(
                        Icons.remove_circle_outline_rounded,
                        color: c.muted,
                      ),
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onEdit((d) => d.addOption(item.id)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(sized ? 'Another size' : 'Add a size'),
            ),
          ),
        ],
      ),
    );
  }
}
