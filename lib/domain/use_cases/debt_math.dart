import '../models/debt.dart';
import '../models/money.dart';

/// Amount still unpaid: debt amount minus its payments, never below zero.
Money debtRemaining(Debt debt, Iterable<DebtPayment> payments) {
  var paid = 0;
  for (final p in payments) {
    if (p.debtId == debt.id) paid += p.amountMinor;
  }
  final left = debt.amountMinor - paid;
  return Money(left < 0 ? 0 : left, debt.currency);
}

/// True when payments cover the whole debt.
bool isDebtSettled(Debt debt, Iterable<DebtPayment> payments) =>
    debtRemaining(debt, payments).minor == 0;
