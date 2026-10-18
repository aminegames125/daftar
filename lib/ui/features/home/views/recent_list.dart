import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../core/format/relative_date.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../view_models/home_summary.dart';

/// "Recent" section of Home: the newest price entries, or a skeleton / empty state.
class RecentList extends StatelessWidget {
  const RecentList({super.key, required this.summary, this.now});

  final AsyncValue<HomeSummary> summary;

  /// Clock for relative dates (tests).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Text('RECENT', style: t.labelSmall),
        ),
        switch (summary) {
          AsyncData(:final value) when value.recent.isEmpty => const EmptyState(
            message: 'Nothing here yet. Tap + to log your first price.',
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final (i, entry) in value.recent.indexed)
                _RecentRow(
                  entry: entry,
                  now: now,
                  showDivider: i < value.recent.length - 1,
                ),
            ],
          ),
          AsyncError() => const EmptyState(
            message: 'Could not load your prices.',
          ),
          _ => const SkeletonList(itemCount: 3),
        },
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.entry,
    required this.now,
    required this.showDivider,
  });

  final RecentPrice entry;
  final DateTime? now;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final icon = entry.isMenu
        ? Icons.menu_book_outlined
        : entry.placeId == null
        ? Icons.public
        : Icons.sell_outlined;
    final target = entry.productId != null
        ? Routes.productDetail(entry.productId!)
        : entry.placeId != null
        ? Routes.placeDetail(entry.placeId!)
        : null;
    final subtitle =
        '${entry.where} · ${formatRelativeDate(entry.seenAt, now: now)}';

    return Semantics(
      button: target != null,
      label:
          '${entry.title}, ${entry.amountText} ${entry.amount.currency.code}, $subtitle',
      excludeSemantics: true,
      child: Squish(
        onTap: target == null ? null : () => context.push(target),
        pressedScale: 0.98,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(bottom: BorderSide(color: c.raised))
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: c.muted),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: t.titleMedium?.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: t.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Text(
                entry.amountText,
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: DaftarType.tabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
