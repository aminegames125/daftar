import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/rate_entries_repository.dart';
import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/features/accounts/rates/rate_chart.dart';
import 'package:daftar/ui/features/accounts/rates/rate_sheet.dart';
import 'package:daftar/ui/features/accounts/rates/rates_providers.dart';
import 'package:daftar/ui/features/accounts/rates/rates_screen.dart';
import 'package:daftar/ui/features/accounts/rates/reverse_calculator_screen.dart';
import 'package:daftar/ui/features/accounts/rates/usd_gain_loss_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../../core/test_app.dart';

class _FakeRates implements RateEntriesRepository {
  _FakeRates(this.items);
  final List<RateEntry> items;
  final saved = <RateEntry>[];

  @override
  Future<RateEntry?> latest() async => items.isEmpty ? null : items.first;
  @override
  Stream<RateEntry?> watchLatest() => Stream.value(items.firstOrNull);
  @override
  Stream<List<RateEntry>> watchAll({DateTime? from, DateTime? to}) =>
      Stream.value(items);
  @override
  Future<void> save(RateEntry entry) async => saved.add(entry);
  @override
  Future<void> delete(String id) async {}
}

RateEntry _e(int day, int rate, [String? note]) => RateEntry(
  id: 'r$day',
  date: DateTime(2026, 10, day),
  tndPerUsdTenThousandths: rate,
  sourceNote: note,
);

final _entries = [
  _e(15, 31250, 'Bank'),
  _e(10, 30900),
  _e(5, 31100, 'Exchange office near the central market'),
];

List<Override> _over(_FakeRates repo) => [
  rateEntriesRepositoryProvider.overrideWithValue(repo),
  rateEntriesProvider.overrideWith((ref) => repo.watchAll()),
  latestRateProvider.overrideWith((ref) => repo.watchLatest()),
];

void main() {
  Future<void> size(WidgetTester t, double w, double h) async {
    t.view.physicalSize = Size(w, h) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  for (final (w, scale) in [(320.0, 2.0), (412.0, 1.0)]) {
    testWidgets('Rates screen has no overflow at $w dp, text x$scale', (
      tester,
    ) async {
      await size(tester, w, 640);
      await tester.pumpWidget(
        testAppScaffold(
          scaffold: const RatesScreen(),
          textScale: scale,
        ).withOverrides(_over(_FakeRates(_entries))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('3.1250'), findsWidgets);
      expect(find.text('Add rate'), findsOneWidget);
    });
  }

  testWidgets('Rates screen empty state', (tester) async {
    await size(tester, 320, 640);
    await tester.pumpWidget(
      testAppScaffold(
        scaffold: const RatesScreen(),
        textScale: 2,
      ).withOverrides(_over(_FakeRates([]))),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('No rates yet'), findsOneWidget);
  });

  testWidgets('RateChart draws with and without motion', (tester) async {
    await size(tester, 320, 640);
    for (final reduce in [true, false]) {
      await tester.pumpWidget(
        testApp(RateChart(entries: _entries), reduceMotion: reduce),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(60, 150));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(testApp(RateChart(entries: [_entries.first])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('rate prompt', () {
    Future<void> open(
      WidgetTester tester,
      _FakeRates repo,
      void Function(int?) onResult, {
      Money? usd = const Money.usd(10000),
    }) async {
      await tester.pumpWidget(
        testApp(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  onResult(await showRatePrompt(context, ref, usdAmount: usd)),
              child: const Text('go'),
            ),
          ),
          overrides: _over(repo),
          reduceMotion: true,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('is prefilled with the latest rate and shows the TND value', (
      tester,
    ) async {
      final repo = _FakeRates(_entries);
      int? result = -1;
      await open(tester, repo, (r) => result = r);
      expect(find.text('3.1250'), findsOneWidget);
      expect(find.text('100.00 USD = 312.500 TND'), findsOneWidget);
      await tester.tap(find.text('Use this rate'));
      await tester.pumpAndSettle();
      expect(result, 31250);
      expect(repo.saved, isEmpty, reason: 'unchanged rate is not duplicated');
    });

    testWidgets('an edited rate is saved and returned', (tester) async {
      final repo = _FakeRates(_entries);
      int? result;
      await open(tester, repo, (r) => result = r);
      await tester.enterText(find.byType(TextField).first, '3.2');
      await tester.pump();
      expect(find.text('100.00 USD = 320.000 TND'), findsOneWidget);
      await tester.tap(find.text('Use this rate'));
      await tester.pumpAndSettle();
      expect(result, 32000);
      expect(repo.saved.single.tndPerUsdTenThousandths, 32000);
    });

    testWidgets('works with no saved rate and rejects an empty field', (
      tester,
    ) async {
      final repo = _FakeRates([]);
      await open(tester, repo, (_) {});
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('no overflow at 320 dp, text x2, keyboard up', (tester) async {
      await size(tester, 320, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 800);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        testApp(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showRatePrompt(
                context,
                ref,
                usdAmount: const Money.usd(123456789),
              ),
              child: const Text('go'),
            ),
          ),
          overrides: _over(_FakeRates(_entries)),
          reduceMotion: true,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('reverse calculator', () {
    testWidgets('TND to USD and back at the latest rate', (tester) async {
      await size(tester, 412, 800);
      await tester.pumpWidget(
        testAppScaffold(scaffold: const ReverseCalculatorScreen())
            .withOverrides(_over(_FakeRates(_entries))),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 USD = 3.1250 TND'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '500');
      await tester.pump();
      expect(find.text('160.00'), findsOneWidget);
      await tester.enterText(fields.at(2), '100');
      await tester.pump();
      expect(find.text('312.500'), findsOneWidget);
      await tester.enterText(fields.at(0), '3');
      await tester.pump();
      expect(find.text('300.000'), findsOneWidget);
    });

    testWidgets('no overflow at 320 dp, text x2', (tester) async {
      await size(tester, 320, 640);
      await tester.pumpWidget(
        testAppScaffold(
          scaffold: const ReverseCalculatorScreen(),
          textScale: 2,
        ).withOverrides(_over(_FakeRates(_entries))),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '123456.789');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('UsdGainLossView', () {
    Widget view({int? avg, int? cur}) => testApp(
      UsdGainLossView(
        balance: const Money.usd(10000),
        averageRate: avg,
        currentRate: cur,
      ),
      textScale: 2,
    );

    testWidgets('shows a gain', (tester) async {
      await size(tester, 320, 640);
      await tester.pumpWidget(view(avg: 30000, cur: 31500));
      expect(
        find.textContaining('315.000', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('gain-loss-value'))).data,
        '+15.000 TND (+5.0%)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a loss', (tester) async {
      await tester.pumpWidget(view(avg: 32000, cur: 31000));
      expect(
        tester.widget<Text>(find.byKey(const Key('gain-loss-value'))).data,
        '-10.000 TND (-3.1%)',
      );
    });

    testWidgets('explains what is missing', (tester) async {
      await tester.pumpWidget(view(avg: null, cur: 31000));
      expect(find.textContaining('Log an exchange'), findsOneWidget);
      await tester.pumpWidget(view(avg: 30000, cur: null));
      expect(find.textContaining('Add today'), findsOneWidget);
    });
  });
}

extension on Widget {
  /// Wraps an already-built test app so extra overrides apply to it.
  Widget withOverrides(List<Override> overrides) =>
      ProviderScope(overrides: overrides, child: this);
}
