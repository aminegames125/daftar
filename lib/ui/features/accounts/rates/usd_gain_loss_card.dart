import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/rates_routes.dart';
import '../../../../data/data_providers.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/rates/rate_math.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import 'rates_providers.dart';

/// What a USD account holds and how it is doing against what it cost.
class UsdPosition {
  const UsdPosition({required this.balance, required this.averageRate});

  /// Opening balance plus every transaction (fees included).
  final Money balance;

  /// Average buy rate weighted by the USD of each exchange; null when no
  /// exchange with a rate was logged.
  final int? averageRate;
}

/// Live position of the USD account [accountId].
final usdPositionProvider = StreamProvider.family<UsdPosition?, String>((
  ref,
  accountId,
) async* {
  final account = await ref
      .watch(accountsRepositoryProvider)
      .getById(accountId);
  if (account == null || account.currency != Currency.usd) {
    yield null;
    return;
  }
  yield* ref
      .watch(transactionsRepositoryProvider)
      .watchForAccount(accountId)
      .map((txs) {
        var minor = account.openingBalanceMinor;
        for (final t in txs) {
          minor += t.balanceEffectMinor;
        }
        return UsdPosition(
          balance: Money.usd(minor),
          averageRate: RateMath.weightedAverageRate(
            RateMath.lotsFromTransactions(txs),
          ),
        );
      });
});

/// Gain or loss of a USD account against its average cost, valued at the latest
/// saved rate. Drop it on an account page: `UsdGainLossCard(accountId: id)`.
/// Shows nothing for accounts that are not in USD. Tapping opens the rates.
class UsdGainLossCard extends ConsumerWidget {
  const UsdGainLossCard({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(usdPositionProvider(accountId)).value;
    if (position == null) return const SizedBox.shrink();
    final latest = ref.watch(latestRateProvider).value;
    return UsdGainLossView(
      balance: position.balance,
      averageRate: position.averageRate,
      currentRate: latest?.tndPerUsdTenThousandths,
      onTap: () => context.push(RatesRoutes.rates),
    );
  }
}

/// The card itself, for callers that already know the numbers.
class UsdGainLossView extends StatelessWidget {
  const UsdGainLossView({
    super.key,
    required this.balance,
    required this.averageRate,
    required this.currentRate,
    this.onTap,
  });

  final Money balance;

  /// Average buy rate x 10 000, or null when unknown.
  final int? averageRate;

  /// Current rate x 10 000, or null when no rate was ever saved.
  final int? currentRate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final avg = averageRate;
    final cur = currentRate;
    final GainLoss? g = avg != null && cur != null
        ? RateMath.gainLoss(
            usdBalance: balance,
            averageRate: avg,
            currentRate: cur,
          )
        : null;

    final Widget content;
    if (cur == null) {
      content = Text(
        'Add today’s USD rate to see what this balance is worth.',
        style: t.bodyMedium,
      );
    } else if (g == null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _worth(context, RateMath.tndForUsd(balance, cur)),
          const SizedBox(height: Space.xs),
          Text(
            'Log an exchange with its rate to see gain or loss.',
            style: t.bodySmall,
          ),
        ],
      );
    } else {
      final color = g.isLoss ? c.coral : (g.isGain ? c.accentText : c.muted);
      final icon = g.isLoss
          ? Icons.trending_down_rounded
          : (g.isGain
                ? Icons.trending_up_rounded
                : Icons.trending_flat_rounded);
      final sign = g.isGain ? '+' : '';
      final pct = g.basisPoints == null
          ? ''
          : ' (${RateMath.formatPercent(g.basisPoints!)})';
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _worth(context, g.value),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: Space.xs),
              Flexible(
                child: Text(
                  '$sign${g.difference.formatWithCode()}$pct',
                  key: const Key('gain-loss-value'),
                  style: t.titleMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Bought at ${RateMath.formatRate(avg!)}, now ${RateMath.formatRate(cur)}',
            style: t.bodySmall,
          ),
        ],
      );
    }

    return Semantics(
      container: true,
      button: onTap != null,
      label: 'USD gain or loss',
      child: Material(
        color: c.surface,
        borderRadius: Radii.cardR,
        child: InkWell(
          borderRadius: Radii.cardR,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Worth today', style: t.bodySmall),
                const SizedBox(height: Space.xs),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _worth(BuildContext context, Money tnd) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: tnd.format(), style: DaftarType.price(28, c.text)),
          TextSpan(
            text: ' TND',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}
