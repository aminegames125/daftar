import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/rates_routes.dart';
import '../../../../app/routes/transfers_routes.dart';
import '../../../../data/data_providers.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/rates/rate_math.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/hold_to_confirm.dart';
import 'rate_chart.dart';
import 'rate_sheet.dart';
import 'rates_providers.dart';

/// The USD/TND rate history: latest rate, average, chart and the list of every
/// saved rate (tap to edit, bin to delete).
class RatesScreen extends ConsumerWidget {
  const RatesScreen({super.key});

  void _back(BuildContext context) =>
      context.canPop() ? context.pop() : context.go(Routes.home);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(rateEntriesProvider);
    final list = entries.value ?? const <RateEntry>[];
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => EmptyState(
            message: 'Could not load the rates.',
            actionLabel: 'Back',
            onAction: () => _back(context),
          ),
          data: (data) => data.isEmpty
              ? _Empty(onBack: () => _back(context))
              : _Body(entries: data, onBack: () => _back(context)),
        ),
      ),
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.swap_vert_rounded,
            label: 'Reverse calculator',
            onTap: () => context.push(RatesRoutes.reverse),
          ),
          ToolbarAction(
            icon: Icons.history_rounded,
            label: 'Exchange log',
            onTap: () => context.push(TransfersRoutes.exchangeLog),
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Add rate',
          onTap: () =>
              showRateEditor(context, latest: list.isEmpty ? null : list.first),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Header(onBack: onBack),
      const Expanded(
        child: Center(
          child: EmptyState(
            message: 'No rates yet. Add today’s USD rate to start.',
          ),
        ),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.gutter, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            constraints: const BoxConstraints.tightFor(
              width: Chrome.minTouch,
              height: Chrome.minTouch,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              'USD rates',
              style: t.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.entries, required this.onBack});

  /// Newest first.
  final List<RateEntry> entries;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final latest = entries.first;
    final rates = [for (final e in entries) e.tndPerUsdTenThousandths];
    final avg = RateMath.simpleAverageRate(rates)!;
    final low = rates.reduce((a, b) => a < b ? a : b);
    final high = rates.reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.only(bottom: Chrome.contentBottomPadding),
      children: [
        _Header(onBack: onBack),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.lg,
            Space.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Latest rate', style: t.bodySmall),
              const SizedBox(height: Space.xs),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: RateMath.formatRate(latest.tndPerUsdTenThousandths),
                      style: DaftarType.price(44, c.text),
                    ),
                    TextSpan(
                      text: '  TND per USD',
                      style: t.bodyMedium?.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              Wrap(
                spacing: Space.xxl,
                runSpacing: Space.md,
                children: [
                  _Stat(label: 'Average', value: RateMath.formatRate(avg)),
                  _Stat(label: 'Lowest', value: RateMath.formatRate(low)),
                  _Stat(label: 'Highest', value: RateMath.formatRate(high)),
                ],
              ),
              if (entries.length > 1) ...[
                const SizedBox(height: Space.xl),
                RateChart(entries: entries),
              ],
              const SizedBox(height: Space.xl),
              Text('History', style: t.titleMedium),
            ],
          ),
        ),
        for (final e in entries) _EntryRow(entry: e, all: entries),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.bodySmall),
        Text(value, style: t.titleMedium),
      ],
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry, required this.all});

  final RateEntry entry;
  final List<RateEntry> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final note = entry.sourceNote;
    final rateText = RateMath.formatRate(entry.tndPerUsdTenThousandths);
    return Semantics(
      container: true,
      label: 'Rate $rateText on ${_fmtDate(entry.date)}',
      child: InkWell(
        onTap: () =>
            showRateEditor(context, existing: entry, latest: all.first),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Chrome.minTouch),
          child: Padding(
            padding: const EdgeInsets.only(
              left: Space.gutter,
              right: Space.sm,
              top: Space.xs,
              bottom: Space.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rateText, style: t.titleMedium),
                      Text(
                        [_fmtDate(entry.date), ?note].join(' · '),
                        style: t.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete rate',
                  constraints: const BoxConstraints.tightFor(
                    width: Chrome.minTouch,
                    height: Chrome.minTouch,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    final ok = await showHoldToConfirm(
                      context,
                      title: 'Delete this rate?',
                      message:
                          '$rateText on ${_fmtDate(entry.date)} will be removed.',
                      label: 'Hold to delete',
                    );
                    if (!ok || !context.mounted) return;
                    await ref
                        .read(rateEntriesRepositoryProvider)
                        .delete(entry.id);
                    if (context.mounted) {
                      FloatingToast.show(context, 'Rate deleted');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
