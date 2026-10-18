import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes/transfers_routes.dart';
import '../../../../../domain/models/account.dart';
import '../../../../../domain/use_cases/transfer_math.dart';
import '../../../../core/format/relative_date.dart';
import '../../../../core/motion/squish.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';
import '../../../../core/theme/daftar_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../view_models/transfer_providers.dart';
import 'exchange_sheet.dart';

/// Names of accounts by id for the log; unknown ids (deleted accounts) read "Account".
Map<String, String> _names(List<Account> accounts) => {
  for (final a in accounts) a.id: a.name,
};

/// Every exchange, newest first. Tap one for its detail.
class ExchangeLogScreen extends ConsumerWidget {
  const ExchangeLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final records = ref.watch(exchangeRecordsProvider);
    final names = _names(ref.watch(transferAccountsProvider).value ?? const []);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.gutter,
                Space.md,
              ),
              child: Row(
                children: [
                  BackSquare(onTap: () => popOrGo(context)),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text('Exchange log', style: t.headlineSmall)),
                ],
              ),
            ),
            Expanded(
              child: records.when(
                loading: () =>
                    const SkeletonList(padding: EdgeInsets.all(Space.gutter)),
                error: (_, _) =>
                    const EmptyState(message: 'Could not load your exchanges.'),
                data: (all) {
                  if (all.isEmpty) {
                    return EmptyState(
                      message: 'No exchanges yet. Change some TND or USD.',
                      actionLabel: 'New exchange',
                      onAction: () => showExchangeSheet(context),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.sm,
                      Space.gutter,
                      Chrome.contentBottomPadding,
                    ),
                    itemCount: all.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Space.md),
                    itemBuilder: (context, i) => _ExchangeCard(
                      record: all[i],
                      names: names,
                      onTap: () => context.push(
                        TransfersRoutes.exchangeDetail(all[i].pairId),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: records.value?.isNotEmpty == true
          ? FloatingActionButton.extended(
              backgroundColor: c.lime,
              foregroundColor: c.onLime,
              onPressed: () => showExchangeSheet(context),
              icon: const Icon(Icons.currency_exchange_rounded),
              label: const Text('Exchange'),
            )
          : null,
    );
  }
}

/// Square back button used by the transfer screens.
class BackSquare extends StatelessWidget {
  const BackSquare({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      button: true,
      label: 'Back',
      excludeSemantics: true,
      child: Squish(
        onTap: onTap,
        child: Container(
          width: Chrome.minTouch,
          height: Chrome.minTouch,
          decoration: BoxDecoration(
            borderRadius: Radii.inputR,
            border: Border.all(color: c.line),
          ),
          child: Icon(Icons.arrow_back_rounded, size: 20, color: c.text),
        ),
      ),
    );
  }
}

/// Goes back, or to the log when there is nothing to pop (deep link).
void popOrGo(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    Navigator.of(context).maybePop();
  } else if (router.canPop()) {
    router.pop();
  } else {
    router.go(TransfersRoutes.exchangeLog);
  }
}

class _ExchangeCard extends StatelessWidget {
  const _ExchangeCard({
    required this.record,
    required this.names,
    required this.onTap,
  });

  final ExchangeRecord record;
  final Map<String, String> names;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final from = names[record.outLeg.accountId] ?? 'Account';
    final to = names[record.inLeg.accountId] ?? 'Account';
    final effective = record.effectiveRate;
    return Semantics(
      button: true,
      label:
          'Exchange ${formatRelativeDate(record.at)}, ${record.sent.formatWithCode()} '
          'to ${record.received.formatWithCode()}',
      excludeSemantics: true,
      child: Squish(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.cardR,
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$from → $to',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(formatRelativeDate(record.at), style: t.bodySmall),
                ],
              ),
              const SizedBox(height: Space.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${record.sent.formatWithCode()} → ${record.received.formatWithCode()}',
                  style: DaftarType.price(20, c.text),
                ),
              ),
              if (effective != null) ...[
                const SizedBox(height: Space.xs),
                Text(
                  'Effective rate ${formatRate(effective)}',
                  style: t.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
