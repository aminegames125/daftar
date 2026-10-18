import 'money.dart';

enum DebtDirection {
  /// Someone owes me.
  owedToMe,

  /// I owe someone.
  iOwe,

  /// I borrowed from my own savings and track it until repaid.
  iOweMyself,
}

class Debt {
  const Debt({
    required this.id,
    required this.name,
    required this.direction,
    required this.amountMinor,
    required this.currency,
    this.note,
    this.dueAt,
    this.sourceAccountId,
  }) : assert(amountMinor >= 0);

  final String id;

  /// The person (or purpose) the debt is with.
  final String name;
  final DebtDirection direction;
  final int amountMinor;
  final Currency currency;
  final String? note;
  final DateTime? dueAt;

  /// Account the money came from / went to, if tracked.
  final String? sourceAccountId;

  Money get amount => Money(amountMinor, currency);
}

class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.debtId,
    required this.amountMinor,
    required this.paidAt,
  }) : assert(amountMinor >= 0);

  final String id;
  final String debtId;
  final int amountMinor;
  final DateTime paidAt;
}
