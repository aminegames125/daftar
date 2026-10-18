import 'money.dart';

enum AccountKind { cash, bank, card, savings, wallet }

/// A place money lives (wallet, bank, card, savings, ...) in one currency.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.currency,
    this.openingBalanceMinor = 0,
    this.includeInTotals = true,
    this.hideAmount = false,
    this.sortOrder = 0,
    this.iconKey = 'wallet',
  });

  final String id;
  final String name;
  final AccountKind kind;
  final Currency currency;

  /// Balance before any logged transaction, in minor units of [currency].
  final int openingBalanceMinor;
  final bool includeInTotals;

  /// Mask this account's amount in the UI.
  final bool hideAmount;
  final int sortOrder;
  final String iconKey;

  Money get openingBalance => Money(openingBalanceMinor, currency);

  Account copyWith({
    String? name,
    AccountKind? kind,
    Currency? currency,
    int? openingBalanceMinor,
    bool? includeInTotals,
    bool? hideAmount,
    int? sortOrder,
    String? iconKey,
  }) => Account(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    currency: currency ?? this.currency,
    openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
    includeInTotals: includeInTotals ?? this.includeInTotals,
    hideAmount: hideAmount ?? this.hideAmount,
    sortOrder: sortOrder ?? this.sortOrder,
    iconKey: iconKey ?? this.iconKey,
  );
}

enum TransactionKind { expense, income, transferOut, transferIn, exchange }

/// One money movement on one [Account].
///
/// [amountMinor] is a magnitude (always >= 0) for every kind except
/// [TransactionKind.exchange], where it is signed: negative = the leg that
/// leaves this account, positive = the leg that arrives. Use [signedAmountMinor]
/// and [balanceEffectMinor] instead of reading the sign by hand.
///
/// Transfers and exchanges are two rows (one per account) sharing a [pairId].
class AccountTransaction {
  const AccountTransaction({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
    this.categoryId,
    this.note,
    this.priceEntryId,
    this.pairId,
    this.feeMinor,
    this.rateTenThousandths,
  }) : assert(
         kind == TransactionKind.exchange || amountMinor >= 0,
         'amount is a magnitude',
       ),
       assert(feeMinor == null || feeMinor >= 0);

  final String id;
  final String accountId;
  final TransactionKind kind;
  final int amountMinor;
  final Currency currency;
  final DateTime occurredAt;
  final String? categoryId;
  final String? note;

  /// "I bought it": the logged price this expense paid for.
  final String? priceEntryId;

  /// Shared by the two legs of a transfer or exchange.
  final String? pairId;

  /// Fee in minor units of [currency], always taken from this account.
  final int? feeMinor;

  /// TND per 1 USD in ten-thousandths (3.1250 -> 31250), when a conversion applies.
  final int? rateTenThousandths;

  /// Effect of the amount alone on the balance (negative = money out).
  int get signedAmountMinor => switch (kind) {
    TransactionKind.expense || TransactionKind.transferOut => -amountMinor,
    TransactionKind.income || TransactionKind.transferIn => amountMinor,
    TransactionKind.exchange => amountMinor,
  };

  /// Effect on the balance including the fee.
  int get balanceEffectMinor => signedAmountMinor - (feeMinor ?? 0);

  Money get amount => Money(amountMinor, currency);
}

/// A recorded USD/TND rate. [tndPerUsdTenThousandths] is TND per 1 USD scaled by 10 000.
class RateEntry {
  const RateEntry({
    required this.id,
    required this.date,
    required this.tndPerUsdTenThousandths,
    this.sourceNote,
  }) : assert(tndPerUsdTenThousandths > 0);

  final String id;
  final DateTime date;
  final int tndPerUsdTenThousandths;
  final String? sourceNote;

  /// Scale of [tndPerUsdTenThousandths].
  static const scale = 10000;
}
