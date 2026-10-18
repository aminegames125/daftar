import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/accounts_repository.dart';
import 'package:daftar/data/repositories/rate_entries_repository.dart';
import 'package:daftar/data/repositories/transactions_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/transfer_math.dart';
import 'package:daftar/ui/core/widgets/hold_to_confirm.dart';
import 'package:daftar/ui/features/accounts/transfers/view_models/transfer_providers.dart';
import 'package:daftar/ui/features/accounts/transfers/views/exchange_detail_screen.dart';
import 'package:daftar/ui/features/accounts/transfers/views/exchange_log_screen.dart';
import 'package:daftar/ui/features/accounts/transfers/views/exchange_sheet.dart';
import 'package:daftar/ui/features/accounts/transfers/views/transfer_sheet.dart';
import 'package:daftar/ui/features/accounts/transfers/views/transfer_widgets.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/test_app.dart';

void main() {
  late AppDatabase db;
  late DriftAccountsRepository accounts;
  late DriftTransactionsRepository txs;
  late DriftRateEntriesRepository rates;

  Account acc(String id, String name, Currency c, int opening) => Account(
    id: id,
    name: name,
    kind: AccountKind.cash,
    currency: c,
    openingBalanceMinor: opening,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    accounts = DriftAccountsRepository(db);
    txs = DriftTransactionsRepository(db);
    rates = DriftRateEntriesRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    await accounts.save(acc('cash', 'Cash', Currency.tnd, 100000));
    await accounts.save(acc('d17', 'D17', Currency.tnd, 0));
    await accounts.save(acc('wise', 'Wise', Currency.usd, 5000));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> size(WidgetTester tester, double w, double h) async {
    tester.view.physicalSize = Size(w, h) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget scoped(Widget child, {double textScale = 1}) => testApp(
    child,
    textScale: textScale,
    reduceMotion: true,
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );

  group('TransferActions', () {
    test('saveTransfer writes both legs atomically', () async {
      final actions = TransferActions(txs, rates);
      final from = acc('cash', 'Cash', Currency.tnd, 100000);
      final to = acc('d17', 'D17', Currency.tnd, 0);
      await accounts.save(from);
      await accounts.save(to);
      await actions.saveTransfer(
        from: from,
        to: to,
        amountMinor: 20000,
        feeMinor: 500,
      );
      final all = await txs.watchAll().first;
      expect(all, hasLength(2));
      final out = all.firstWhere((t) => t.kind == TransactionKind.transferOut);
      final inn = all.firstWhere((t) => t.kind == TransactionKind.transferIn);
      expect(out.pairId, inn.pairId);
      expect(out.feeMinor, 500);
      expect(inn.amountMinor, 20000);
    });

    test('saveExchange saves a rate only when it changed', () async {
      final actions = TransferActions(txs, rates);
      final from = acc('cash', 'Cash', Currency.tnd, 100000);
      final to = acc('wise', 'Wise', Currency.usd, 0);
      await accounts.save(from);
      await accounts.save(to);

      await actions.saveExchange(
        from: from,
        to: to,
        sendMinor: 31250,
        rateTenThousandths: 31250,
      );
      expect((await rates.watchAll().first), hasLength(1));

      await actions.saveExchange(
        from: from,
        to: to,
        sendMinor: 31250,
        rateTenThousandths: 31250,
      );
      expect((await rates.watchAll().first), hasLength(1));

      await actions.saveExchange(
        from: from,
        to: to,
        sendMinor: 31250,
        rateTenThousandths: 31400,
        feeMinor: 100,
      );
      final saved = await rates.watchAll().first;
      expect(saved, hasLength(2));
      expect(saved.first.tndPerUsdTenThousandths, 31400);

      final records = groupExchanges(await txs.watchAll().first);
      expect(records, hasLength(3));
      expect(
        records
            .expand((r) => [r.outLeg, r.inLeg])
            .every((t) => t.pairId != null),
        isTrue,
      );
    });

    test('deleteExchange removes both legs', () async {
      final actions = TransferActions(txs, rates);
      final from = acc('cash', 'Cash', Currency.tnd, 100000);
      final to = acc('wise', 'Wise', Currency.usd, 0);
      await accounts.save(from);
      await accounts.save(to);
      await actions.saveExchange(
        from: from,
        to: to,
        sendMinor: 31250,
        rateTenThousandths: 31250,
      );
      final record = groupExchanges(await txs.watchAll().first).single;
      await actions.deleteExchange(record.pairId);
      expect(await txs.watchAll().first, isEmpty);
    });
  });

  group('MoneyMoveAnimation', () {
    Widget anim({VoidCallback? onDone}) => MoneyMoveAnimation(
      fromName: 'Cash',
      toName: 'D17',
      fromBefore: const Money.tnd(100000),
      fromAfter: const Money.tnd(80000),
      toBefore: const Money.tnd(0),
      toAfter: const Money.tnd(20000),
      chipLabel: '20.000 TND',
      onDone: onDone,
    );

    testWidgets('plays, counts the balances and calls onDone', (tester) async {
      var done = 0;
      await tester.pumpWidget(
        testApp(anim(onDone: () => done++), reduceMotion: false),
      );
      expect(find.text('100.000'), findsOneWidget);
      expect(done, 0);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('100.000'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('80.000'), findsOneWidget);
      expect(find.text('20.000'), findsOneWidget);
      expect(done, 1);
    });

    testWidgets('reduced motion shows the final frame at once', (tester) async {
      var done = 0;
      await tester.pumpWidget(
        testApp(anim(onDone: () => done++), reduceMotion: true),
      );
      await tester.pump();
      expect(find.text('80.000'), findsOneWidget);
      expect(find.text('20.000'), findsOneWidget);
      expect(done, 1);
    });
  });

  group('TransferSheet', () {
    testWidgets('moves money between two accounts and writes both legs', (
      tester,
    ) async {
      await seed(tester);
      await tester.pumpWidget(scoped(const TransferSheet(accountId: 'cash')));
      await settle(tester);

      // Source preselected, destination auto-picked (only one other TND account).
      expect(find.text('Balance 100.000 TND'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField).first, '25');
      await tester.enterText(find.byType(TextField).at(1), '0.5');
      await tester.pump();
      await tester.tap(find.text('Move money'));
      await settle(tester);

      final all = (await tester.runAsync(() => txs.watchAll().first))!;
      expect(all, hasLength(2));
      final out = all.firstWhere((t) => t.kind == TransactionKind.transferOut);
      expect(out.accountId, 'cash');
      expect(out.amountMinor, 25000);
      expect(out.feeMinor, 500);
      expect(
        all.firstWhere((t) => t.kind == TransactionKind.transferIn).accountId,
        'd17',
      );
      // Animation ended on its final frame.
      expect(find.text('Done'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    testWidgets('warns about insufficient balance but still allows saving', (
      tester,
    ) async {
      await seed(tester);
      await tester.pumpWidget(scoped(const TransferSheet(accountId: 'cash')));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '500');
      await tester.pump();
      expect(find.textContaining('more than the balance'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    testWidgets('does not offer a USD account as destination', (tester) async {
      await seed(tester);
      await tester.pumpWidget(scoped(const TransferSheet(accountId: 'cash')));
      await settle(tester);
      // "To" shows only D17; D17 is in both rows.
      expect(find.textContaining('Wise'), findsOneWidget);
      expect(find.textContaining('D17'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    for (final (w, s) in [(320.0, 1.0), (320.0, 2.0)]) {
      testWidgets('no overflow at ${w.toInt()} dp, text x$s', (tester) async {
        await seed(tester);
        await size(tester, w, 640);
        await tester.pumpWidget(
          scoped(const TransferSheet(accountId: 'cash'), textScale: s),
        );
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, '500');
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      });
    }
  });

  group('ExchangeSheet', () {
    testWidgets(
      'prefills the latest rate, shows the effective rate live and saves',
      (tester) async {
        await seed(tester);
        await tester.runAsync(
          () => rates.save(
            RateEntry(
              id: 'r1',
              date: DateTime.utc(2026, 10, 1),
              tndPerUsdTenThousandths: 31250,
            ),
          ),
        );
        await tester.pumpWidget(scoped(const ExchangeSheet(accountId: 'cash')));
        await settle(tester);

        // TND source: only the USD account can receive. Rate prefilled.
        expect(
          tester
              .widget<TextField>(find.byType(TextField).at(1))
              .controller!
              .text,
          '3.1250',
        );
        // fields: amount, rate, fee, note
        await tester.enterText(find.byType(TextField).first, '312.5');
        await tester.pump();
        expect(find.text('100.00 USD'), findsOneWidget);
        expect(
          find.textContaining('Effective rate: 3.1250 TND per USD'),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField).at(2), '3');
        await tester.pump();
        expect(
          find.textContaining('Effective rate (with fee): 3.1550'),
          findsOneWidget,
        );

        // Edit the rate -> new rate saved.
        await tester.enterText(find.byType(TextField).at(1), '3.2');
        await tester.pump();
        expect(find.textContaining('New rate'), findsOneWidget);
        await tester.ensureVisible(find.text('Exchange').last);
        await tester.pump();
        await tester.tap(find.text('Exchange').last);
        await settle(tester);

        final records = groupExchanges(
          (await tester.runAsync(() => txs.watchAll().first))!,
        );
        expect(records, hasLength(1));
        expect(records.single.sent, const Money.tnd(312500));
        expect(records.single.fee, const Money.tnd(3000));
        expect(records.single.rateTenThousandths, 32000);
        expect(
          (await tester.runAsync(() => rates.latest()))!
              .tndPerUsdTenThousandths,
          32000,
        );
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      },
    );

    testWidgets('USD source offers only the TND accounts', (tester) async {
      await seed(tester);
      await tester.pumpWidget(scoped(const ExchangeSheet(accountId: 'wise')));
      await settle(tester);
      expect(find.text('Balance 50.00 USD'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    for (final (w, s) in [(320.0, 1.0), (320.0, 2.0)]) {
      testWidgets('no overflow at ${w.toInt()} dp, text x$s', (tester) async {
        await seed(tester);
        await size(tester, w, 640);
        await tester.pumpWidget(
          scoped(const ExchangeSheet(accountId: 'cash'), textScale: s),
        );
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, '312.5');
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      });
    }
  });

  group('Exchange log and detail', () {
    Future<String> addExchange(WidgetTester tester) async {
      final actions = TransferActions(txs, rates);
      await tester.runAsync(
        () => actions.saveExchange(
          from: acc('cash', 'Cash', Currency.tnd, 0),
          to: acc('wise', 'Wise', Currency.usd, 0),
          sendMinor: 312500,
          rateTenThousandths: 31250,
          feeMinor: 3000,
        ),
      );
      return groupExchanges(
        (await tester.runAsync(() => txs.watchAll().first))!,
      ).single.pairId;
    }

    testWidgets('lists exchanges with amounts and effective rate', (
      tester,
    ) async {
      await seed(tester);
      await addExchange(tester);
      await tester.pumpWidget(scoped(const ExchangeLogScreen()));
      await settle(tester);
      expect(find.text('Cash → Wise'), findsOneWidget);
      expect(find.text('312.500 TND → 100.00 USD'), findsOneWidget);
      expect(find.text('Effective rate 3.1550'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    testWidgets('shows an empty state', (tester) async {
      await seed(tester);
      await tester.pumpWidget(scoped(const ExchangeLogScreen()));
      await settle(tester);
      expect(find.textContaining('No exchanges yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    testWidgets('detail deletes both legs only after the hold', (tester) async {
      await seed(tester);
      final pairId = await addExchange(tester);
      await tester.pumpWidget(scoped(ExchangeDetailScreen(pairId: pairId)));
      await settle(tester);
      expect(find.text('312.500 TND'), findsOneWidget);
      expect(find.text('3.1550 TND per USD'), findsOneWidget);

      await tester.ensureVisible(find.byType(HoldToConfirm));
      await tester.pump();
      // A tap alone does nothing.
      await tester.tap(find.byType(HoldToConfirm));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        (await tester.runAsync(() => txs.watchAll().first))!,
        hasLength(2),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldToConfirm)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await settle(tester);
      expect((await tester.runAsync(() => txs.watchAll().first))!, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    testWidgets('log and detail do not overflow at 320 dp, text x2', (
      tester,
    ) async {
      await seed(tester);
      final pairId = await addExchange(tester);
      await size(tester, 320, 640);
      await tester.pumpWidget(scoped(const ExchangeLogScreen(), textScale: 2));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        scoped(ExchangeDetailScreen(pairId: pairId), textScale: 2),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  });
}
