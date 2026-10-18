import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/debt.dart';
import '../../../../domain/models/ids.dart';
import 'debt_items.dart';

/// Writes for the debts screens (views never touch repositories directly).
class DebtActions {
  DebtActions(this._ref);

  final Ref _ref;

  Future<void> save(Debt debt) => _ref.read(debtsRepositoryProvider).save(debt);

  Future<void> delete(String id) =>
      _ref.read(debtsRepositoryProvider).delete(id);

  Future<void> deletePayment(String id) =>
      _ref.read(debtsRepositoryProvider).deletePayment(id);

  /// True when [debt] has a source account in the same currency, so a payment
  /// can also be logged there.
  Future<bool> canMirror(Debt debt) async {
    final id = debt.sourceAccountId;
    if (id == null) return false;
    final account = await _ref.read(accountsRepositoryProvider).getById(id);
    return account != null && account.currency == debt.currency;
  }

  /// Adds a repayment of [amountMinor] (clamped to what is left) and returns
  /// true when this payment settled the debt. With [mirrorToAccount] it also
  /// logs the matching transaction on the source account: income when money
  /// comes back to me (they pay me, or I repay my own savings), expense when
  /// I pay someone.
  Future<bool> addPayment(
    DebtItem item,
    int amountMinor, {
    bool mirrorToAccount = false,
  }) async {
    final debt = item.debt;
    final amount = amountMinor > item.remaining.minor
        ? item.remaining.minor
        : amountMinor;
    if (amount <= 0) return false;
    final payment = await _ref
        .read(debtsRepositoryProvider)
        .addPayment(debt.id, amount);
    final accountId = debt.sourceAccountId;
    if (mirrorToAccount && accountId != null && await canMirror(debt)) {
      await _ref
          .read(transactionsRepositoryProvider)
          .save(
            AccountTransaction(
              id: newId(),
              accountId: accountId,
              kind: debt.direction == DebtDirection.iOwe
                  ? TransactionKind.expense
                  : TransactionKind.income,
              amountMinor: amount,
              currency: debt.currency,
              occurredAt: payment.paidAt,
              note: switch (debt.direction) {
                DebtDirection.owedToMe => 'Debt repaid by ${debt.name}',
                DebtDirection.iOwe => 'Debt repaid to ${debt.name}',
                DebtDirection.iOweMyself => 'Paid back to savings',
              },
            ),
          );
    }
    return amount == item.remaining.minor;
  }
}

final debtActionsProvider = Provider<DebtActions>(DebtActions.new);

/// Display helpers for [DebtDirection].
extension DebtDirectionText on DebtDirection {
  String get label => switch (this) {
    DebtDirection.owedToMe => 'They owe me',
    DebtDirection.iOwe => 'I owe them',
    DebtDirection.iOweMyself => 'I owe myself',
  };

  /// Label of the person field.
  String get personLabel => switch (this) {
    DebtDirection.owedToMe => 'Who owes you?',
    DebtDirection.iOwe => 'Who do you owe?',
    DebtDirection.iOweMyself => 'What for?',
  };

  /// What a payment means, for the add-payment sheet.
  String get paymentVerb => switch (this) {
    DebtDirection.owedToMe => 'They paid me',
    DebtDirection.iOwe => 'I paid',
    DebtDirection.iOweMyself => 'I paid myself back',
  };

  IconData get icon => switch (this) {
    DebtDirection.owedToMe => Icons.south_west_rounded,
    DebtDirection.iOwe => Icons.north_east_rounded,
    DebtDirection.iOweMyself => Icons.savings_outlined,
  };
}
