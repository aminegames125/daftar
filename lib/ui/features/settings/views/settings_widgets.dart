import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// A titled group of settings rows on a `surface` card.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: Radii.cardR,
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: Space.lg,
                      endIndent: Space.lg,
                      color: c.line,
                    ),
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One settings row: icon tile, title, optional subtitle and a trailing widget.
/// Tappable when [onTap] is set.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
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
              child: Icon(icon, size: 18, color: c.muted),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleMedium),
                  if (subtitle != null) Text(subtitle!, style: t.bodySmall),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Space.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: Squish(onTap: onTap, pressedScale: 0.99, child: row),
    );
  }
}

/// A settings row with a switch.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      toggled: value,
      label: title,
      child: SettingsTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              },
        trailing: ExcludeSemantics(
          child: IgnorePointer(
            child: Switch(
              value: value,
              onChanged: onChanged == null ? null : (_) {},
            ),
          ),
        ),
      ),
    );
  }
}

/// Single-choice chips (selected = lime 12% fill, lime border, lime text, check).
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final (value, label) in options)
          Semantics(
            button: true,
            selected: value == selected,
            label: label,
            excludeSemantics: true,
            onTap: () => onSelected(value),
            child: Squish(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(value);
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: Chrome.minTouch),
                padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == selected
                      ? c.lime.withValues(alpha: 0.12)
                      : c.raised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: value == selected ? c.accentText : c.line,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value == selected) ...[
                      Icon(Icons.check_rounded, size: 16, color: c.accentText),
                      const SizedBox(width: Space.xs + 2),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: t.labelMedium?.copyWith(
                          color: value == selected ? c.accentText : c.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
