import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/debt.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/features/debts/view_models/debt_items.dart';
import 'package:daftar/ui/features/debts/views/add_payment_sheet.dart';
import 'package:daftar/ui/features/debts/views/debt_detail_screen.dart';
import 'package:daftar/ui/features/debts/views/debt_form_screen.dart';
import 'package:daftar/ui/features/debts/views/debts_card.dart';
import 'package:daftar/ui/features/debts/views/debts_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/test_app.dart';

final _now = DateTime(2026, 10, 17, 12);

Debt _debt(
  String id,
  DebtDirection dir, {
  int amount = 120000,
  Currency currency = Currency.tnd,
  DateTime? due,
  String name = 'Sami Ben Salah with a rather long name',
}) => Debt(
  id: id,
  name: name,
  direction: dir,
  amountMinor: amount,
  currency: currency,
  dueAt: due,
  note: 'For the car repair and a very long explanation of it',
);

List<DebtItem> _items() => buildDebtItems(
  [
    _debt('1', DebtDirection.owedToMe, due: DateTime(2026, 9, 1)),
    _debt('2', DebtDirection.owedToMe, currency: Currency.usd, amount: 5000),
    _debt('3', DebtDirection.iOwe),
    _debt('4', DebtDirection.iOweMyself, name: 'Phone'),
    _debt('5', DebtDirection.iOwe, amount: 1000, name: 'Settled one'),
  ],
  [
    DebtPayment(id: 'p1', debtId: '1', amountMinor: 20000, paidAt: _now),
    DebtPayment(id: 'p2', debtId: '1', amountMinor: 10000, paidAt: _now),
    DebtPayment(id: 'p5', debtId: '5', amountMinor: 1000, paidAt: _now),
  ],
  _now,
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  double width = 360,
  double height = 640,
  double textScale = 1,
  bool dark = true,
  List<DebtItem>? items,
}) async {
  tester.view.physicalSize = Size(width, height) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    testApp(
      screen,
      textScale: textScale,
      dark: dark,
      reduceMotion: true,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        debtItemsProvider.overrideWithValue(AsyncData(items ?? _items())),
        debtAccountsProvider.overrideWith(
          (ref) => Stream.value([
            const Account(
              id: 'acc',
              name: 'A very long savings account name',
              kind: AccountKind.savings,
              currency: Currency.tnd,
            ),
          ]),
        ),
      ],
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'list groups by direction, shows totals per currency and overdue',
    (tester) async {
      await _pump(tester, const DebtsScreen(), height: 2400);
      expect(find.text('They owe me'), findsOneWidget);
      expect(find.text('I owe them'), findsOneWidget);
      expect(find.text('I owe myself'), findsOneWidget);
      // 120.000 - 30.000 = 90.000 TND open, and 5.00 USD kept separate.
      expect(find.textContaining('90.000'), findsWidgets);
      expect(find.textContaining('50.00'), findsWidgets);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('Settled ·'), findsOneWidget);
    },
  );

  testWidgets('empty list invites to add a debt', (tester) async {
    await _pump(tester, const DebtsScreen(), items: const []);
    expect(find.textContaining('No debts yet'), findsOneWidget);
  });

  testWidgets('detail shows payments, remaining and the lime action', (
    tester,
  ) async {
    await _pump(tester, const DebtDetailScreen(debtId: '1'));
    expect(find.text('Add payment'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.byTooltip('Delete payment'), findsNWidgets(2));
  });

  testWidgets('settled detail has no add-payment action', (tester) async {
    await _pump(tester, const DebtDetailScreen(debtId: '5'));
    expect(find.text('Settled'), findsOneWidget);
    expect(find.text('Add payment'), findsNothing);
  });

  testWidgets('home card shows owed to me and by me', (tester) async {
    final container = ProviderContainer(
      overrides: [debtItemsProvider.overrideWithValue(AsyncData(_items()))],
    );
    addTearDown(container.dispose);
    expect(container.read(debtTotalsProvider).owedToMe[Currency.tnd], 90000);
    await _pump(tester, const DebtsCard());
    expect(find.text('Owed to me'), findsOneWidget);
    expect(find.text('Owed by me'), findsOneWidget);
  });

  testWidgets('form validates and add-payment rejects too much', (
    tester,
  ) async {
    await _pump(tester, const DebtFormScreen());
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter an amount'), findsOneWidget);
  });

  testWidgets('add payment sheet: error above remaining, pay all fills', (
    tester,
  ) async {
    final item = _items().first;
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showAddPaymentSheet(context, item),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay all'));
    await tester.pump();
    expect(find.text('90.000'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '95');
    await tester.tap(find.widgetWithText(FilledButton, 'Add payment'));
    await tester.pump();
    expect(find.textContaining('More than'), findsOneWidget);
  });

  group('no overflow at 320 dp and text scale 2.0', () {
    final screens = <String, Widget>{
      'list': const DebtsScreen(),
      'detail': const DebtDetailScreen(debtId: '1'),
      'detail settled': const DebtDetailScreen(debtId: '5'),
      'form': const DebtFormScreen(),
      'card': const DebtsCard(),
    };
    for (final e in screens.entries) {
      for (final dark in [true, false]) {
        testWidgets('${e.key} ${dark ? 'dark' : 'light'}', (tester) async {
          await _pump(tester, e.value, width: 320, textScale: 2, dark: dark);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('add payment sheet', (tester) async {
      final item = _items().first;
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddPaymentSheet(context, item),
            child: const Text('open'),
          ),
        ),
        width: 320,
        textScale: 2,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
