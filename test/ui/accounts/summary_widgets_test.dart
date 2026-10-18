import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/period_summary.dart';
import 'package:daftar/domain/use_cases/summary_period.dart';
import 'package:daftar/ui/features/accounts/summary/view_models/summary_providers.dart';
import 'package:daftar/ui/features/accounts/summary/views/accounts_summary_card.dart';
import 'package:daftar/ui/features/accounts/summary/views/summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../core/test_app.dart';

final _now = DateTime(2026, 10, 17, 10);

class _Hidden extends SummaryHideAmounts {
  _Hidden(this.value);
  final bool value;
  @override
  bool build() => value;
}

PeriodSummary _summary(SummaryPeriod p, {bool rate = true}) => summarizePeriod(
  period: p,
  accounts: const [
    Account(
      id: 'a',
      name: 'Cash',
      kind: AccountKind.cash,
      currency: Currency.tnd,
    ),
  ],
  transactions: [
    for (final (kind, amount, cur, cat) in [
      (TransactionKind.income, 500000, Currency.tnd, null),
      (TransactionKind.expense, 120000, Currency.tnd, 'food'),
      (TransactionKind.expense, 30000, Currency.tnd, 'bills'),
      (TransactionKind.expense, 2500, Currency.usd, null),
    ])
      AccountTransaction(
        id: '$amount',
        accountId: 'a',
        kind: kind,
        amountMinor: amount,
        currency: cur,
        occurredAt: DateTime(2026, 10, 5),
        categoryId: cat,
      ),
  ],
  rate: rate
      ? RateEntry(
          id: 'r',
          date: DateTime(2026, 10, 1),
          tndPerUsdTenThousandths: 31250,
        )
      : null,
);

List<Override> overridesFor({bool hidden = false, bool rate = true}) => [
  summaryClockProvider.overrideWithValue(() => _now),
  summaryHideAmountsProvider.overrideWith(() => _Hidden(hidden)),
  periodSummaryProvider.overrideWith(
    (ref, period) => AsyncValue.data(_summary(period, rate: rate)),
  ),
  summaryCategoriesProvider.overrideWithValue(const AsyncValue.data({})),
  currentMonthSummaryProvider.overrideWith(
    (ref) => AsyncValue.data(
      _summary(
        SummaryPeriod.containing(SummaryGranularity.month, _now),
        rate: rate,
      ),
    ),
  ),
];

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    bool hidden = false,
    bool rate = true,
    double width = 400,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 800) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        const SummaryScreen(),
        textScale: scale,
        overrides: overridesFor(hidden: hidden, rate: rate),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows income, spending, net and the all-in-TND rate', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('500.000 TND'), findsOneWidget);
    expect(find.text('150.000 TND'), findsOneWidget); // 120 + 30 spending
    expect(find.text('+350.000 TND'), findsOneWidget);
    expect(find.text('25.00 USD'), findsWidgets);
    expect(find.text('≈ all in TND'), findsOneWidget);
    expect(find.textContaining('3.1250'), findsOneWidget);
    expect(find.text('Spending by category'), findsNWidgets(2));
  });

  testWidgets('says clearly when there is no rate', (tester) async {
    await pumpScreen(tester, rate: false);
    expect(find.textContaining('No exchange rate saved yet'), findsOneWidget);
  });

  testWidgets('hidden amounts show bullets, never numbers', (tester) async {
    await pumpScreen(tester, hidden: true);
    expect(find.text('••••'), findsWidgets);
    expect(find.textContaining('500.000'), findsNothing);
    expect(find.text('USD'), findsOneWidget); // the header only
  });

  testWidgets('granularity switch and stepper change the period', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Day'));
    await tester.pump();
    expect(find.text('17 Oct 2026'), findsOneWidget);
    await tester.tap(find.text('Week'));
    await tester.pump();
    expect(find.text('12 Oct – 18 Oct 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous period'));
    await tester.pump();
    expect(find.text('5 Oct – 11 Oct 2026'), findsOneWidget);
    await tester.tap(find.text('Year'));
    await tester.pump();
    expect(find.text('2026'), findsOneWidget);
    // The current period has no "next".
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    expect(next.onPressed, isNull);
  });

  for (final w in [320.0, 360.0]) {
    testWidgets('does not overflow at ${w}dp and text scale 2.0', (
      tester,
    ) async {
      await pumpScreen(tester, width: w, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Week'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('summary card shows the month net and opens on tap', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      testApp(
        AccountsSummaryCard(onTap: () => opened++),
        overrides: overridesFor(),
      ),
    );
    await tester.pump();
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('+350.000 TND'), findsOneWidget);
    expect(find.text('-25.00 USD'), findsOneWidget);
    await tester.tap(find.text('This month'));
    expect(opened, 1);
  });

  testWidgets('summary card hides amounts and fits 320dp at scale 2', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        const AccountsSummaryCard(),
        textScale: 2,
        overrides: overridesFor(hidden: true),
      ),
    );
    await tester.pump();
    expect(find.text('••••'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
