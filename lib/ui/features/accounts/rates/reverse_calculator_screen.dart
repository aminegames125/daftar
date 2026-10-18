import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/rates_routes.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/rates/rate_math.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/money_field.dart';
import 'rate_field.dart';
import 'rate_sheet.dart';
import 'rates_providers.dart';

/// "I need 500 TND, how many USD?" Type either amount and the other follows at
/// the chosen rate (prefilled with the latest saved rate).
class ReverseCalculatorScreen extends ConsumerStatefulWidget {
  const ReverseCalculatorScreen({super.key});

  @override
  ConsumerState<ReverseCalculatorScreen> createState() =>
      _ReverseCalculatorScreenState();
}

class _ReverseCalculatorScreenState
    extends ConsumerState<ReverseCalculatorScreen> {
  final _rateText = TextEditingController();
  final _tndText = TextEditingController();
  final _usdText = TextEditingController();
  int? _rate;
  Money? _tnd;
  Money? _usd;
  bool _tndIsSource = true;
  bool _rateSeeded = false;

  @override
  void dispose() {
    _rateText.dispose();
    _tndText.dispose();
    _usdText.dispose();
    super.dispose();
  }

  void _seedRate(int rate) {
    _rateSeeded = true;
    _rate = rate;
    _rateText.text = RateMath.formatRate(rate);
  }

  void _recompute() {
    final rate = _rate;
    if (rate == null) return;
    if (_tndIsSource) {
      final tnd = _tnd;
      _usd = tnd == null ? null : RateMath.usdForTnd(tnd, rate);
      _usdText.text = _usd == null ? '' : moneyInputText(_usd!);
    } else {
      final usd = _usd;
      _tnd = usd == null ? null : RateMath.tndForUsd(usd, rate);
      _tndText.text = _tnd == null ? '' : moneyInputText(_tnd!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final latest = ref.watch(latestRateProvider);
    if (!_rateSeeded && latest.hasValue) {
      final l = latest.value;
      if (l != null) _seedRate(l.tndPerUsdTenThousandths);
      _rateSeeded = true;
    }
    final rate = _rate;

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Space.sm,
            Space.sm,
            Space.gutter,
            Chrome.contentBottomPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    constraints: const BoxConstraints.tightFor(
                      width: Chrome.minTouch,
                      height: Chrome.minTouch,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(Routes.home),
                  ),
                  Expanded(
                    child: Text(
                      'Reverse calculator',
                      style: t.headlineSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Space.lg),
                    RateField(
                      controller: _rateText,
                      fontSize: 32,
                      errorText: rate == null && _rateText.text.isNotEmpty
                          ? 'Enter a rate like 3.1250'
                          : null,
                      onChanged: (s) => setState(() {
                        _rate = RateMath.tryParseRate(s);
                        _recompute();
                      }),
                    ),
                    const SizedBox(height: Space.xl),
                    MoneyField(
                      controller: _tndText,
                      label: 'I need (TND)',
                      fontSize: 36,
                      onChanged: (m) => setState(() {
                        _tndIsSource = true;
                        _tnd = m;
                        _recompute();
                      }),
                    ),
                    const SizedBox(height: Space.lg),
                    MoneyField(
                      controller: _usdText,
                      label: 'I pay (USD)',
                      currency: Currency.usd,
                      fontSize: 36,
                      onChanged: (m) => setState(() {
                        _tndIsSource = false;
                        _usd = m;
                        _recompute();
                      }),
                    ),
                    if (rate != null) ...[
                      const SizedBox(height: Space.xl),
                      Text(
                        '1 USD = ${RateMath.formatRate(rate)} TND',
                        style: t.bodyMedium?.copyWith(color: c.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.show_chart_rounded,
            label: 'Rate history',
            onTap: () => context.push(RatesRoutes.rates),
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Save rate',
          onTap: rate == null
              ? null
              : () => showRateEditor(
                  context,
                  latest: latest.value,
                  initialRate: rate,
                ),
        ),
      ),
    );
  }
}
