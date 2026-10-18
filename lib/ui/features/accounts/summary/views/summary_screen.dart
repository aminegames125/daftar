import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../domain/models/money.dart';
import '../../../../../domain/use_cases/period_summary.dart';
import '../../../../../domain/use_cases/summary_period.dart';
import '../../../../core/motion/daftar_motion.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';
import '../../../../core/widgets/empty_state.dart';
import '../view_models/summary_providers.dart';
import 'category_bars.dart';
import 'summary_format.dart';

/// Income, spending and net for a day / week / month / year, per currency, with
/// a spending breakdown by category and an "all in TND" total.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(summaryPeriodProvider);
    final hidden = ref.watch(summaryHideAmountsProvider);
    final summary = ref.watch(periodSummaryProvider(period));
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary'),
        actions: [
          IconButton(
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            constraints: const BoxConstraints(
              minWidth: Chrome.minTouch,
              minHeight: Chrome.minTouch,
            ),
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              ref.read(summaryHideAmountsProvider.notifier).set(!hidden);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Chrome.contentBottomPadding,
        ),
        children: [
          _GranularitySwitch(
            value: period.granularity,
            onChanged: (g) {
              HapticFeedback.selectionClick();
              ref.read(summaryPeriodProvider.notifier).setGranularity(g);
            },
          ),
          const SizedBox(height: Space.md),
          _Stepper(period: period),
          const SizedBox(height: Space.lg),
          summary.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Space.xxxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              'Could not load the summary.',
              style: TextStyle(color: c.coral),
            ),
            data: (s) => SummaryBody(summary: s, hidden: hidden),
          ),
        ],
      ),
    );
  }
}

class _GranularitySwitch extends StatelessWidget {
  const _GranularitySwitch({required this.value, required this.onChanged});

  final SummaryGranularity value;
  final ValueChanged<SummaryGranularity> onChanged;

  static String _name(SummaryGranularity g) => switch (g) {
    SummaryGranularity.day => 'Day',
    SummaryGranularity.week => 'Week',
    SummaryGranularity.month => 'Month',
    SummaryGranularity.year => 'Year',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final g in SummaryGranularity.values)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: g == SummaryGranularity.year ? 0 : Space.xs,
              ),
              child: Semantics(
                button: true,
                selected: g == value,
                label: _name(g),
                excludeSemantics: true,
                onTap: () => onChanged(g),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(g),
                  child: AnimatedContainer(
                    duration: DaftarMotion.reduced(context)
                        ? Duration.zero
                        : DaftarMotion.fast,
                    curve: DaftarMotion.standard,
                    constraints: const BoxConstraints(
                      minHeight: Chrome.minTouch,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                    decoration: BoxDecoration(
                      color: g == value ? c.text : c.raised,
                      borderRadius: Radii.pillR,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _name(g),
                        maxLines: 1,
                        style: t.labelLarge?.copyWith(
                          color: g == value ? c.background : c.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Stepper extends ConsumerWidget {
  const _Stepper({required this.period});

  final SummaryPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(summaryPeriodProvider.notifier);
    final canNext = !period.isCurrentOrFuture(ref.read(summaryClockProvider)());
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous period',
          constraints: const BoxConstraints(
            minWidth: Chrome.minTouch,
            minHeight: Chrome.minTouch,
          ),
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () {
            HapticFeedback.selectionClick();
            controller.previous();
          },
        ),
        Expanded(
          child: Text(
            period.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Next period',
          constraints: const BoxConstraints(
            minWidth: Chrome.minTouch,
            minHeight: Chrome.minTouch,
          ),
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: canNext
              ? () {
                  HapticFeedback.selectionClick();
                  controller.next();
                }
              : null,
        ),
      ],
    );
  }
}

/// The cards under the stepper. Public so it can be tested without the
/// providers.
class SummaryBody extends ConsumerWidget {
  const SummaryBody({super.key, required this.summary, required this.hidden});

  final PeriodSummary summary;
  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (summary.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.xxl),
        child: EmptyState(
          message: 'Nothing recorded in this period.',
          markSize: 56,
        ),
      );
    }
    final names = ref.watch(summaryCategoriesProvider).value ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final cs in [summary.tnd, summary.usd])
          if (!cs.isEmpty) ...[
            _CurrencyCard(
              summary: cs,
              hidden: hidden,
              categoryName: (id) => names[id]?.name ?? 'Other',
            ),
            const SizedBox(height: Space.md),
          ],
        _AllInTndCard(summary: summary, hidden: hidden),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.text,
    this.color,
    this.bold = false,
  });

  final String label;
  final String text;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final style = (bold ? t.titleMedium : t.bodyMedium)?.copyWith(
      color: color,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 2,
            child: Text(label, style: t.bodyMedium?.copyWith(color: color)),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            flex: 3,
            child: Text(
              text,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({
    required this.summary,
    required this.hidden,
    required this.categoryName,
  });

  final CurrencySummary summary;
  final bool hidden;
  final String Function(String? id) categoryName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final top = summary.categories.isEmpty
        ? 0
        : summary.categories.first.spendingMinor;
    final net = summary.net;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(summary.currency.code, style: t.titleSmall),
          const SizedBox(height: Space.sm),
          _AmountRow(
            label: 'Income',
            text: summaryMoney(summary.income, hidden: hidden),
          ),
          _AmountRow(
            label: 'Spending',
            text: summaryMoney(summary.spending, hidden: hidden),
          ),
          Divider(color: c.line, height: Space.lg),
          _AmountRow(
            label: 'Net',
            bold: true,
            color: hidden || !net.isNegative ? null : c.coral,
            text: summaryMoney(net, hidden: hidden, signed: true),
          ),
          if (summary.categories.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Text('Spending by category', style: t.labelMedium),
            const SizedBox(height: Space.md),
            CategoryBars(
              rows: [
                for (final cat in summary.categories)
                  CategoryBarData(
                    label: categoryName(cat.categoryId),
                    amountText: summaryMoney(
                      Money(cat.spendingMinor, summary.currency),
                      hidden: hidden,
                    ),
                    fraction: top == 0 ? 0 : cat.spendingMinor / top,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AllInTndCard extends StatelessWidget {
  const _AllInTndCard({required this.summary, required this.hidden});

  final PeriodSummary summary;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final all = summary.allInTnd;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AmountRow(
            label: '≈ all in TND',
            bold: true,
            text: all == null
                ? '—'
                : summaryMoney(all.net, hidden: hidden, signed: true),
          ),
          const SizedBox(height: Space.xs),
          Text(
            all == null
                ? 'No exchange rate saved yet, so USD cannot be converted. '
                      'Add a rate in Accounts to see the total.'
                : 'USD converted at ${formatRate(all.rateTenThousandths)} TND '
                      'per USD (latest rate, ${_date(all.rateDate)}).',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }
}
