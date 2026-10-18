@Skip(
  'Hangs waiting on Drift streams under the fake clock; rewrite the seeding (TODO)',
)
library;

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/bills_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/bill.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/features/bills/view_models/bills_providers.dart';
import 'package:daftar/ui/features/bills/views/bill_detail_screen.dart';
import 'package:daftar/ui/features/bills/views/bill_form_screen.dart';
import 'package:daftar/ui/features/bills/views/bills_due_card.dart';
import 'package:daftar/ui/features/bills/views/bills_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../core/test_app.dart';
import 'bills_view_model_test.dart' show FakeScheduler;

final _today = DateTime(2026, 10, 17, 12);

Bill _bill(
  String name,
  DateTime due, {
  int amount = 45000,
  Currency currency = Currency.tnd,
  bool active = true,
  BillCycle cycle = BillCycle.monthly,
}) => Bill(
  id: name,
  name: name,
  amountMinor: amount,
  currency: currency,
  cycle: cycle,
  nextDueAt: due,
  isActive: active,
);

final _sample = [
  _bill('STEG electricity and gas bill', DateTime(2026, 10, 14)),
  _bill(
    'Netflix',
    DateTime(2026, 10, 20),
    amount: 1599,
    currency: Currency.usd,
  ),
  _bill('Rent', DateTime(2026, 11, 5), amount: 1250000),
  _bill('Gym', DateTime(2026, 12, 5), amount: 60000, active: false),
];

void main() {
  late AppDatabase db;
  late FakeScheduler scheduler;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    scheduler = FakeScheduler();
  });
  tearDown(() => db.close());

  List<Override> overrides([List<Bill>? bills]) => [
    appDatabaseProvider.overrideWithValue(db),
    reminderSchedulerProvider.overrideWithValue(scheduler),
    billsNowProvider.overrideWithValue(_today),
    if (bills != null) billsProvider.overrideWith((ref) => Stream.value(bills)),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    List<Bill>? bills,
    double w = 360,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(w, 700) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        KeyedSubtree(key: UniqueKey(), child: screen),
        textScale: textScale,
        reduceMotion: true,
        overrides: overrides(bills),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('list: chips, per-currency totals, paused last', (tester) async {
    await pump(tester, const BillsScreen(), bills: _sample);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Due soon'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    // 45.000 + 1250.000 TND (paused gym ignored) and 15.99 USD, never mixed.
    expect(find.textContaining('1 295.000'), findsOneWidget);
    expect(find.textContaining('15.99'), findsWidgets);
    expect(find.text('Add bill'), findsOneWidget);
  });

  testWidgets('list: empty state', (tester) async {
    await pump(tester, const BillsScreen(), bills: const []);
    expect(find.textContaining('No bills yet'), findsOneWidget);
  });

  for (final (w, scale) in [(320.0, 2.0), (320.0, 1.0), (360.0, 2.0)]) {
    testWidgets('no overflow at ${w}dp, text x$scale', (tester) async {
      await pump(
        tester,
        const BillsScreen(),
        bills: _sample,
        w: w,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      await pump(
        tester,
        const BillsDueCard(),
        bills: _sample,
        w: w,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      await pump(
        tester,
        BillDetailScreen(billId: _sample.first.id),
        bills: _sample,
        w: w,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      await pump(
        tester,
        BillFormScreen(billId: _sample[1].id),
        bills: _sample,
        w: w,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      await pump(
        tester,
        const BillFormScreen(),
        bills: _sample,
        w: w,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('due card lists what is due in 7 days with sums per currency', (
    tester,
  ) async {
    await pump(tester, const BillsDueCard(), bills: _sample);
    expect(find.text('2 bills due'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Rent'), findsNothing);
    expect(find.textContaining('Overdue by 3 days'), findsOneWidget);
  });

  testWidgets('due card: nothing due', (tester) async {
    await pump(
      tester,
      const BillsDueCard(),
      bills: [_bill('Rent', DateTime(2026, 11, 5))],
    );
    expect(find.text('Nothing due in the next 7 days'), findsOneWidget);
  });

  testWidgets('mark as paid records a payment and moves the due date', (
    tester,
  ) async {
    final repo = DriftBillsRepository(db);
    await tester.runAsync(
      () => repo.save(_bill('STEG', DateTime(2026, 10, 20))),
    );
    await pump(tester, const BillDetailScreen(billId: 'STEG'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('No payments yet.'), findsOneWidget);

    await tester.tap(find.text('Mark as paid'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump();

    final bill = await tester.runAsync(() => repo.getById('STEG'));
    expect(bill!.nextDueAt, DateTime(2026, 11, 20));
    expect(find.text('No payments yet.'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('form: shows errors when saving an empty bill', (tester) async {
    await pump(tester, const BillFormScreen());
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Give the bill a name'), findsOneWidget);
    expect(find.text('Enter an amount'), findsOneWidget);
  });

  testWidgets('form: custom days field appears for "Every N days"', (
    tester,
  ) async {
    await pump(tester, const BillFormScreen());
    expect(find.text('Number of days'), findsNothing);
    await tester.tap(find.text('Every N days'));
    await tester.pump();
    expect(find.text('Number of days'), findsOneWidget);
  });
}
