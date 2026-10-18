import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/repositories/bills_repository.dart';
import '../../../../data/services/reminders/reminder_scheduler.dart';
import '../../../../domain/models/bill.dart';
import '../../../../domain/use_cases/bill_reminder_plan.dart';

/// Today, as seen by the bills screens. Tests override it with a fixed date.
final billsNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// The notification scheduler. Tests override it with a fake.
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => LocalNotificationsScheduler(),
);

/// All live bills (paused ones included), soonest due date first.
final billsProvider = StreamProvider<List<Bill>>(
  (ref) => ref.watch(billsRepositoryProvider).watchAll(),
);

/// One bill by id (null while loading or when it no longer exists).
final billProvider = Provider.family<Bill?, String>((ref, id) {
  final bills = ref.watch(billsProvider).value;
  if (bills == null) return null;
  for (final b in bills) {
    if (b.id == id) return b;
  }
  return null;
});

/// Payment history of one bill, newest first.
final billPaymentsProvider = StreamProvider.family<List<BillPayment>, String>(
  (ref, billId) => ref.watch(billsRepositoryProvider).watchPayments(billId),
);

/// Keeps the scheduled reminders in step with the bills: every change (add, edit,
/// paid, pause, delete) and the first read after app start reschedule everything.
/// Watch it from any screen that shows bills.
final billReminderSyncProvider = Provider<void>((ref) {
  final scheduler = ref.watch(reminderSchedulerProvider);
  ref.listen<AsyncValue<List<Bill>>>(billsProvider, (_, next) {
    final bills = next.value;
    if (bills == null) return;
    scheduler.replaceAll(planReminders(bills, ref.read(billsNowProvider)));
  }, fireImmediately: true);
});

/// The reminders that should exist for [bills] at [now].
List<Reminder> planReminders(List<Bill> bills, DateTime now) {
  final reminders = <Reminder>[];
  for (final b in bills) {
    final when = reminderTime(b, now);
    if (when == null) continue;
    final text = reminderText(b);
    reminders.add(
      Reminder(
        id: reminderId(b.id),
        title: text.title,
        body: text.body,
        when: when,
      ),
    );
  }
  return reminders;
}

/// What the screens can do to bills. Reminders follow through
/// [billReminderSyncProvider].
class BillActions {
  BillActions(this._repo, this._scheduler);

  final BillsRepository _repo;
  final ReminderScheduler _scheduler;

  /// Saves the bill and asks for the notification permission when it has a reminder.
  /// A denied permission is fine: the bill is saved either way.
  Future<void> save(Bill bill) async {
    await _repo.save(bill);
    if (bill.isActive) await _scheduler.requestPermission();
  }

  /// Records a payment and moves the due date one cycle on.
  Future<BillPayment> markPaid(String billId) => _repo.recordPayment(billId);

  Future<void> setActive(Bill bill, bool active) =>
      _repo.save(bill.copyWith(isActive: active));

  Future<void> delete(String billId) => _repo.delete(billId);

  Future<void> deletePayment(String paymentId) =>
      _repo.deletePayment(paymentId);
}

final billActionsProvider = Provider<BillActions>(
  (ref) => BillActions(
    ref.watch(billsRepositoryProvider),
    ref.watch(reminderSchedulerProvider),
  ),
);
