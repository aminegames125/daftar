import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../domain/use_cases/transfer_math.dart';
import '../../../../core/format/relative_date.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';
import '../../../../core/theme/daftar_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/hold_to_confirm.dart';
import '../view_models/transfer_providers.dart';
import 'exchange_log_screen.dart';

/// One exchange: both amounts, the rates, the fee and a hold-to-confirm delete
/// that removes both legs.
class ExchangeDetailScreen extends ConsumerWidget {
  const ExchangeDetailScreen({super.key, required this.pairId});

  final String pairId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final records = ref.watch(exchangeRecordsProvider);
    final accounts = ref.watch(transferAccountsProvider).value ?? const [];
    final names = {for (final a in accounts) a.id: a.name};
    final record = records.value?.where((r) => r.pairId == pairId).firstOrNull;

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
                  Expanded(child: Text('Exchange', style: t.headlineSmall)),
                ],
              ),
            ),
            Expanded(
              child: record == null
                  ? EmptyState(
                      message: records.isLoading
                          ? 'Loading...'
                          : 'This exchange no longer exists.',
                    )
                  : _Body(
                      record: record,
                      from: names[record.outLeg.accountId] ?? 'Account',
                      to: names[record.inLeg.accountId] ?? 'Account',
                      onDelete: () async {
                        await ref
                            .read(transferActionsProvider)
                            .deleteExchange(pairId);
                        if (context.mounted) popOrGo(context);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.record,
    required this.from,
    required this.to,
    required this.onDelete,
  });

  final ExchangeRecord record;
  final String from;
  final String to;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final rate = record.rateTenThousandths;
    final effective = record.effectiveRate;
    final fee = record.fee;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Chrome.contentBottomPadding,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(Space.xl),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.cardR,
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sent from $from', style: t.bodySmall),
              const SizedBox(height: Space.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  record.sent.formatWithCode(),
                  style: DaftarType.price(32, c.text),
                ),
              ),
              const SizedBox(height: Space.lg),
              Text('Received in $to', style: t.bodySmall),
              const SizedBox(height: Space.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  record.received.formatWithCode(),
                  style: DaftarType.price(32, c.text),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        _Row(label: 'Date', value: formatRelativeDate(record.at)),
        if (rate != null)
          _Row(label: 'Rate', value: '${formatRate(rate)} TND per USD'),
        if (effective != null)
          _Row(
            label: 'Effective rate',
            value: '${formatRate(effective)} TND per USD',
          ),
        if (fee != null) _Row(label: 'Fee', value: fee.formatWithCode()),
        if (record.note != null) _Row(label: 'Note', value: record.note!),
        const SizedBox(height: Space.xxxl),
        HoldToConfirm(label: 'Hold to delete', onConfirmed: onDelete),
        const SizedBox(height: Space.sm),
        Text(
          'This removes both sides of the exchange and puts the balances back.',
          style: t.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.bodySmall),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: t.bodyMedium),
          ),
        ],
      ),
    );
  }
}
