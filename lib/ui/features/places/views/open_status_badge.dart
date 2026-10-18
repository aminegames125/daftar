import 'package:flutter/material.dart';

import '../../../../domain/models/place.dart';
import '../../../../domain/place_logic/open_now.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// Open-now badge. Hidden when the place has no hours. The state is also written
/// out in words, never colour alone.
class OpenStatusBadge extends StatelessWidget {
  const OpenStatusBadge({
    super.key,
    required this.hours,
    this.now,
    this.chip = false,
  });

  final OpeningHours? hours;

  /// Fixed clock for tests.
  final DateTime? now;

  /// Draw as a filled chip (place page) instead of a dot + text (list rows).
  final bool chip;

  @override
  Widget build(BuildContext context) {
    final time = now ?? DateTime.now();
    final status = openStatusAt(hours, time);
    if (status.state == OpenState.unknown) return const SizedBox.shrink();

    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final label = describeOpenStatus(status, time);
    final dot = switch (status.state) {
      OpenState.open => c.lime,
      OpenState.closingSoon => c.amber,
      _ => c.muted,
    };
    final text = switch (status.state) {
      OpenState.open => c.accentText,
      OpenState.closingSoon => c.amber,
      _ => c.muted,
    };

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.sm - 2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.labelMedium?.copyWith(color: chip ? text : c.muted),
          ),
        ),
      ],
    );
    if (!chip) {
      return Semantics(label: label, excludeSemantics: true, child: row);
    }
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm - 2,
        ),
        decoration: BoxDecoration(
          color: status.isOpen ? text.withValues(alpha: 0.12) : c.raised,
          borderRadius: Radii.chipR,
        ),
        child: row,
      ),
    );
  }
}
