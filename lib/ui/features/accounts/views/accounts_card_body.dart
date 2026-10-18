import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/accounts_providers.dart';
import 'account_widgets.dart';

/// Lower part of the Accounts card on Home: the total per currency (TND and USD
/// are never added) and the eye that hides every balance.
class AccountsCardBody extends ConsumerWidget {
  const AccountsCardBody({
    super.key,
    required this.foreground,
    required this.secondary,
  });

  final Color foreground;
  final Color secondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final overview = ref.watch(accountsOverviewProvider).value;
    if (overview == null) return const SizedBox.shrink();
    if (overview.accounts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No accounts yet',
            style: t.bodySmall?.copyWith(color: secondary),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Tap to add your first account',
            style: t.titleMedium?.copyWith(color: foreground),
          ),
        ],
      );
    }
    final totals = [
      for (final cur in Currency.values)
        if (overview.totals[cur] != null) overview.totals[cur]!,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                overview.accounts.length == 1
                    ? '1 account'
                    : '${overview.accounts.length} accounts',
                style: t.bodySmall?.copyWith(color: secondary),
              ),
              for (final m in totals)
                AmountText(
                  m,
                  size: totals.length > 1 ? 24 : 32,
                  color: foreground,
                ),
            ],
          ),
        ),
        HideAmountsButton(color: secondary),
      ],
    );
  }
}
