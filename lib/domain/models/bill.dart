import 'money.dart';

enum BillCycle { monthly, yearly, weekly, customDays }

/// A recurring bill or subscription (STEG, Netflix, ...).
class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.currency,
    required this.cycle,
    required this.nextDueAt,
    this.customDays,
    this.reminderDaysBefore = 3,
    this.isActive = true,
    this.iconKey = 'receipt',
    this.categoryId,
  }) : assert(
         cycle != BillCycle.customDays ||
             (customDays != null && customDays > 0),
         'customDays cycle needs customDays > 0',
       ),
       assert(reminderDaysBefore >= 0);

  final String id;
  final String name;
  final int amountMinor;
  final Currency currency;
  final BillCycle cycle;

  /// Length of the cycle when [cycle] is [BillCycle.customDays].
  final int? customDays;
  final DateTime nextDueAt;
  final int reminderDaysBefore;
  final bool isActive;
  final String iconKey;
  final String? categoryId;

  Money get amount => Money(amountMinor, currency);

  Bill copyWith({
    String? name,
    int? amountMinor,
    Currency? currency,
    BillCycle? cycle,
    int? customDays,
    DateTime? nextDueAt,
    int? reminderDaysBefore,
    bool? isActive,
    String? iconKey,
    String? categoryId,
  }) => Bill(
    id: id,
    name: name ?? this.name,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    cycle: cycle ?? this.cycle,
    customDays: customDays ?? this.customDays,
    nextDueAt: nextDueAt ?? this.nextDueAt,
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    isActive: isActive ?? this.isActive,
    iconKey: iconKey ?? this.iconKey,
    categoryId: categoryId ?? this.categoryId,
  );
}

/// A payment of a [Bill] (history).
class BillPayment {
  const BillPayment({
    required this.id,
    required this.billId,
    required this.amountMinor,
    required this.paidAt,
  });

  final String id;
  final String billId;
  final int amountMinor;
  final DateTime paidAt;
}
