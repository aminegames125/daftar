import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/models/place.dart';
import '../../../../domain/place_logic/open_now.dart';
import '../../../../domain/place_logic/opening_hours_edit.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// Weekly opening hours: per day an open/closed switch and one or two time
/// ranges ("08:00-13:00" and "15:00-22:00").
class OpeningHoursEditor extends StatelessWidget {
  const OpeningHoursEditor({
    super.key,
    required this.hours,
    required this.onDayChanged,
    required this.onCopyToAll,
  });

  final OpeningHours hours;
  final void Function(String day, List<TimeRange> ranges) onDayChanged;
  final ValueChanged<String> onCopyToAll;

  static const _defaultRange = (open: '08:00', close: '22:00');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        for (final day in weekdayKeys) ...[
          _DayRow(
            day: day,
            ranges: hours.days[day] ?? const [],
            onOpenChanged: (open) =>
                onDayChanged(day, open ? [_defaultRange] : const []),
            onRangesChanged: (r) => onDayChanged(day, r),
            onCopyToAll: () => onCopyToAll(day),
          ),
          if (day != weekdayKeys.last) Divider(color: c.line),
        ],
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.ranges,
    required this.onOpenChanged,
    required this.onRangesChanged,
    required this.onCopyToAll,
  });

  final String day;
  final List<TimeRange> ranges;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<List<TimeRange>> onRangesChanged;
  final VoidCallback onCopyToAll;

  bool get _open => ranges.isNotEmpty;

  Future<TimeRange?> _pick(BuildContext context, TimeRange current) async {
    final open = await _pickTime(context, current.open, 'Opens');
    if (open == null || !context.mounted) return null;
    final close = await _pickTime(context, current.close, 'Closes');
    if (close == null) return null;
    return (open: open, close: close);
  }

  Future<String?> _pickTime(
    BuildContext context,
    String initial,
    String help,
  ) async {
    final minutes = parseHm(initial) ?? 0;
    final picked = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    return picked == null ? null : formatHm(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(dayLabel(day), style: t.titleMedium),
              ),
              Text(_open ? 'Open' : 'Closed', style: t.bodySmall),
              const Spacer(),
              Semantics(
                label: '${dayLabel(day)} open',
                toggled: _open,
                child: Switch(
                  value: _open,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    onOpenChanged(v);
                  },
                ),
              ),
            ],
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (var i = 0; i < ranges.length; i++)
                    _RangeChip(
                      range: ranges[i],
                      onTap: () async {
                        final next = await _pick(context, ranges[i]);
                        if (next != null) {
                          onRangesChanged([...ranges]..[i] = next);
                        }
                      },
                      onRemove: ranges.length > 1
                          ? () => onRangesChanged([...ranges]..removeAt(i))
                          : null,
                    ),
                  TextButton(
                    onPressed: onCopyToAll,
                    child: const Text('Same every day'),
                  ),
                  if (ranges.length < 2)
                    Squish(
                      onTap: () => onRangesChanged([
                        ...ranges,
                        (open: '15:00', close: '22:00'),
                      ]),
                      child: Semantics(
                        button: true,
                        label: 'Add a second time range for ${dayLabel(day)}',
                        excludeSemantics: true,
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: Chrome.minTouch,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.md,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '+ Split',
                            style: t.labelMedium?.copyWith(color: c.muted),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.range, required this.onTap, this.onRemove});

  final TimeRange range;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final text = '${range.open}–${range.close}';
    return Container(
      constraints: const BoxConstraints(minHeight: Chrome.minTouch),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: Radii.inputR,
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Change hours $text',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: Radii.inputR,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.md,
                ),
                child: Text(
                  text,
                  style: t.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Semantics(
              button: true,
              label: 'Remove $text',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: Radii.inputR,
                onTap: onRemove,
                child: SizedBox.square(
                  dimension: Chrome.minTouch,
                  child: Icon(Icons.close_rounded, size: 18, color: c.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
