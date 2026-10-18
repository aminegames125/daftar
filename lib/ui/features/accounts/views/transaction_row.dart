import 'package:flutter/material.dart';

import '../../../../domain/models/account.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../settings/views/list_icons.dart';
import 'account_widgets.dart';

extension TransactionKindLabel on TransactionKind {
  String get label => switch (this) {
    TransactionKind.expense => 'Expense',
    TransactionKind.income => 'Income',
    TransactionKind.transferOut => 'Transfer out',
    TransactionKind.transferIn => 'Transfer in',
    TransactionKind.exchange => 'Exchange',
  };

  /// Only plain expenses and income are edited here; transfers and exchanges
  /// are managed by their own flows.
  bool get isEditableHere =>
      this == TransactionKind.expense || this == TransactionKind.income;
}

/// One transaction in a day group: category icon, title (note or category),
/// subtitle (category, "bought" link) and the signed amount.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.transaction,
    this.category,
    this.onTap,
  });

  final AccountTransaction transaction;
  final Category? category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final tx = transaction;
    final note = tx.note?.trim();
    final title = (note != null && note.isNotEmpty)
        ? note
        : (category?.name ?? tx.kind.label);
    final hasNote = note != null && note.isNotEmpty;
    final subtitle = [
      if (hasNote && category != null) category!.name,
      tx.kind.label,
    ].join(' · ');
    final isIncome = tx.signedAmountMinor > 0;
    return Semantics(
      button: onTap != null,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.inputR,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: Chrome.minTouch + Space.md,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                Icon(
                  category != null
                      ? iconForKey(category!.iconKey)
                      : (isIncome
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded),
                  size: 22,
                  color: c.muted,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(fontSize: 15),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall,
                      ),
                      if (tx.priceEntryId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sell_outlined,
                                size: 14,
                                color: c.accentText,
                              ),
                              const SizedBox(width: Space.xs),
                              Flexible(
                                child: Text(
                                  'Bought from a logged price',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall?.copyWith(
                                    color: c.accentText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AmountText(
                      Money(tx.signedAmountMinor, tx.currency),
                      size: 18,
                      plus: true,
                      color: isIncome ? c.accentText : c.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
