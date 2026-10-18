import '../../../../domain/models/bill.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/money.dart';

/// Longest reminder lead time the form offers.
const int maxReminderDays = 14;

/// The values typed into the bill form, and their validation. Pure Dart so it can
/// be unit tested; the form widget only edits it.
class BillDraft {
  const BillDraft({
    this.id,
    this.name = '',
    this.amount,
    this.currency = Currency.tnd,
    this.cycle = BillCycle.monthly,
    this.customDays,
    required this.nextDueAt,
    this.reminderDaysBefore = 3,
    this.iconKey = 'receipt',
    this.isActive = true,
  });

  /// A new bill due on [today].
  factory BillDraft.fresh(DateTime today) =>
      BillDraft(nextDueAt: DateTime(today.year, today.month, today.day));

  factory BillDraft.fromBill(Bill b) => BillDraft(
    id: b.id,
    name: b.name,
    amount: b.amount,
    currency: b.currency,
    cycle: b.cycle,
    customDays: b.customDays,
    nextDueAt: b.nextDueAt,
    reminderDaysBefore: b.reminderDaysBefore,
    iconKey: b.iconKey,
    isActive: b.isActive,
  );

  /// Null for a new bill.
  final String? id;
  final String name;
  final Money? amount;
  final Currency currency;
  final BillCycle cycle;
  final int? customDays;
  final DateTime nextDueAt;
  final int reminderDaysBefore;
  final String iconKey;
  final bool isActive;

  bool get isNew => id == null;

  BillDraft copyWith({
    String? name,
    Money? amount,
    bool clearAmount = false,
    Currency? currency,
    BillCycle? cycle,
    int? customDays,
    bool clearCustomDays = false,
    DateTime? nextDueAt,
    int? reminderDaysBefore,
    String? iconKey,
  }) => BillDraft(
    id: id,
    name: name ?? this.name,
    amount: clearAmount ? null : (amount ?? this.amount),
    currency: currency ?? this.currency,
    cycle: cycle ?? this.cycle,
    customDays: clearCustomDays ? null : (customDays ?? this.customDays),
    nextDueAt: nextDueAt ?? this.nextDueAt,
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    iconKey: iconKey ?? this.iconKey,
    isActive: isActive,
  );

  String? get nameError => name.trim().isEmpty ? 'Give the bill a name' : null;

  String? get amountError {
    final a = amount;
    if (a == null || a.minor <= 0) return 'Enter an amount';
    return null;
  }

  String? get customDaysError {
    if (cycle != BillCycle.customDays) return null;
    final d = customDays;
    if (d == null || d < 1 || d > 3650) return 'Enter 1 to 3650 days';
    return null;
  }

  bool get isValid =>
      nameError == null && amountError == null && customDaysError == null;

  /// The bill to save. Call only when [isValid].
  Bill toBill() {
    assert(isValid);
    return Bill(
      id: id ?? newId(),
      name: name.trim(),
      amountMinor: amount!.minor,
      currency: currency,
      cycle: cycle,
      customDays: cycle == BillCycle.customDays ? customDays : null,
      nextDueAt: nextDueAt,
      reminderDaysBefore: reminderDaysBefore,
      isActive: isActive,
      iconKey: iconKey,
    );
  }
}
