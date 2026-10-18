import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/reminders/reminder_scheduler.dart';
import 'package:daftar/domain/models/bill.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/features/bills/view_models/bill_draft.dart';
import 'package:daftar/ui/features/bills/view_models/bills_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeScheduler implements ReminderScheduler {
  final List<List<Reminder>> calls = [];
  int permissionAsks = 0;
  bool granted = false;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return granted;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async =>
      calls.add(reminders);
}

void main() {
  final today = DateTime(2026, 10, 17, 12);
  late AppDatabase db;
  late FakeScheduler scheduler;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    scheduler = FakeScheduler();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        billsNowProvider.overrideWithValue(today),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  BillDraft draft({String name = 'STEG', DateTime? due}) => BillDraft(
    name: name,
    amount: const Money.tnd(45000),
    nextDueAt: due ?? DateTime(2026, 10, 25),
  );

  group('BillDraft', () {
    test('validates name, amount and custom days', () {
      final empty = BillDraft.fresh(today);
      expect(empty.nameError, isNotNull);
      expect(empty.amountError, isNotNull);
      expect(empty.isValid, isFalse);
      expect(draft().isValid, isTrue);
      expect(
        draft().copyWith(cycle: BillCycle.customDays).customDaysError,
        isNotNull,
      );
      expect(
        draft().copyWith(cycle: BillCycle.customDays, customDays: 10).isValid,
        isTrue,
      );
    });

    test('toBill trims, drops stale custom days, round-trips', () {
      final bill = draft(name: '  STEG ').copyWith(customDays: 9).toBill();
      expect(bill.name, 'STEG');
      expect(bill.customDays, isNull);
      final again = BillDraft.fromBill(bill);
      expect(again.id, bill.id);
      expect(again.toBill().amountMinor, 45000);
    });
  });

  test(
    'saving then marking paid advances the due date and keeps history',
    () async {
      final actions = container.read(billActionsProvider);
      final bill = draft().toBill();
      await actions.save(bill);
      expect(scheduler.permissionAsks, 1);

      await actions.markPaid(bill.id);
      final repo = container.read(billsRepositoryProvider);
      final after = await repo.getById(bill.id);
      expect(after!.nextDueAt, DateTime(2026, 11, 25));
      final payments = await repo.watchPayments(bill.id).first;
      expect(payments.single.amountMinor, 45000);
    },
  );

  test('reminders follow the bills: add, pay, pause, delete', () async {
    container.listen(billReminderSyncProvider, (_, _) {});
    await settle();
    expect(scheduler.calls.last, isEmpty);

    final actions = container.read(billActionsProvider);
    final bill = draft(due: DateTime(2026, 10, 25)).toBill();
    await actions.save(bill);
    await settle();
    expect(scheduler.calls.last.single.when, DateTime(2026, 10, 22, 9));

    await actions.markPaid(bill.id);
    await settle();
    expect(scheduler.calls.last.single.when, DateTime(2026, 11, 22, 9));

    await actions.setActive(container.read(billProvider(bill.id))!, false);
    await settle();
    expect(scheduler.calls.last, isEmpty);

    await actions.delete(bill.id);
    await settle();
    expect(container.read(billsProvider).value, isEmpty);
    expect(scheduler.calls.last, isEmpty);
  });

  test('a bill whose reminder moment has passed is not scheduled', () {
    final plan = planReminders([
      draft(due: DateTime(2026, 10, 18)).toBill(),
    ], today);
    expect(plan, isEmpty);
  });
}
