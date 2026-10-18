import '../models/account.dart';
import '../models/ids.dart';
import '../models/money.dart';

/// Why a transfer or exchange cannot be saved yet. Null from the validators means "ready".
enum TransferIssue {
  pickFrom('Pick the account the money leaves.'),
  pickTo('Pick the account the money goes to.'),
  sameAccount('Choose two different accounts.'),
  currencyMismatch('Both accounts must use the same currency.'),
  needsOneOfEach('An exchange needs one TND and one USD account.'),
  amountRequired('Enter an amount above zero.'),
  rateRequired('Enter the exchange rate.'),
  feeInvalid('The fee cannot be negative.');

  const TransferIssue(this.message);
  final String message;
}

/// First blocking problem of a same-currency transfer, or null when it can be saved.
/// Not having enough money is **not** a blocker; see [isShort].
TransferIssue? validateTransfer({
  required Account? from,
  required Account? to,
  required int amountMinor,
  int feeMinor = 0,
}) {
  if (from == null) return TransferIssue.pickFrom;
  if (to == null) return TransferIssue.pickTo;
  if (from.id == to.id) return TransferIssue.sameAccount;
  if (from.currency != to.currency) return TransferIssue.currencyMismatch;
  if (amountMinor <= 0) return TransferIssue.amountRequired;
  if (feeMinor < 0) return TransferIssue.feeInvalid;
  return null;
}

/// First blocking problem of a TND <-> USD exchange, or null.
TransferIssue? validateExchange({
  required Account? from,
  required Account? to,
  required int amountMinor,
  required int rateTenThousandths,
  int feeMinor = 0,
}) {
  if (from == null) return TransferIssue.pickFrom;
  if (to == null) return TransferIssue.pickTo;
  if (from.id == to.id) return TransferIssue.sameAccount;
  if (from.currency == to.currency) return TransferIssue.needsOneOfEach;
  if (amountMinor <= 0) return TransferIssue.amountRequired;
  if (rateTenThousandths <= 0) return TransferIssue.rateRequired;
  if (feeMinor < 0) return TransferIssue.feeInvalid;
  return null;
}

/// True when [balanceMinor] cannot cover [amountMinor] plus [feeMinor]. A warning only.
bool isShort({
  required int balanceMinor,
  required int amountMinor,
  int feeMinor = 0,
}) => amountMinor + feeMinor > balanceMinor;

/// Two legs of a transfer: `transferOut` on [from] (fee on top), `transferIn` on [to].
List<AccountTransaction> buildTransferLegs({
  required Account from,
  required Account to,
  required int amountMinor,
  int feeMinor = 0,
  required DateTime at,
  String? note,
  String Function()? idGenerator,
}) {
  final gen = idGenerator ?? newId;
  final pairId = gen();
  return [
    AccountTransaction(
      id: gen(),
      accountId: from.id,
      kind: TransactionKind.transferOut,
      amountMinor: amountMinor,
      currency: from.currency,
      occurredAt: at,
      note: note,
      pairId: pairId,
      feeMinor: feeMinor > 0 ? feeMinor : null,
    ),
    AccountTransaction(
      id: gen(),
      accountId: to.id,
      kind: TransactionKind.transferIn,
      amountMinor: amountMinor,
      currency: to.currency,
      occurredAt: at,
      note: note,
      pairId: pairId,
    ),
  ];
}

int _roundDiv(int numerator, int denominator) =>
    (numerator * 2 + denominator) ~/ (denominator * 2);

/// Amount that arrives when [sendMinor] of [from] is exchanged at [rateTenThousandths]
/// (TND per 1 USD x 10 000). Rounded half up to the smallest unit.
int convertMinor({
  required int sendMinor,
  required Currency from,
  required int rateTenThousandths,
}) => switch (from) {
  // millimes -> cents: m / 1000 / rate * 100 = m * 1000 / rate(ten-thousandths)
  Currency.tnd => _roundDiv(sendMinor * 1000, rateTenThousandths),
  // cents -> millimes: c / 100 * rate * 1000 = c * rate / 1000
  Currency.usd => _roundDiv(sendMinor * rateTenThousandths, 1000),
};

/// The rate actually obtained once the fee is counted: TND per 1 USD x 10 000,
/// from everything that left the source account (amount + fee) and what arrived.
/// Returns null when nothing arrived.
int? effectiveRateTenThousandths({
  required Currency from,
  required int sendMinor,
  required int feeMinor,
  required int receivedMinor,
}) {
  if (receivedMinor <= 0) return null;
  final spent = sendMinor + feeMinor;
  final tndMillimes = from == Currency.tnd ? spent : receivedMinor;
  final usdCents = from == Currency.tnd ? receivedMinor : spent;
  if (usdCents <= 0) return null;
  // TND per USD = millimes / 1000 / (cents / 100) = millimes / (cents * 10); x 10 000.
  return _roundDiv(tndMillimes * 1000, usdCents);
}

/// "3.1250" for 31250.
String formatRate(int tenThousandths) {
  final whole = tenThousandths ~/ RateEntry.scale;
  final frac = (tenThousandths % RateEntry.scale).toString().padLeft(4, '0');
  return '$whole.$frac';
}

/// Parses "3.125" / "3,1250" into ten-thousandths; null when invalid or zero.
int? parseRate(String input) {
  final t = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{0,4})?$').hasMatch(t)) return null;
  final parts = t.split('.');
  final frac = (parts.length > 1 ? parts[1] : '').padRight(4, '0');
  final v = int.parse(parts[0]) * RateEntry.scale + int.parse(frac);
  return v > 0 ? v : null;
}

/// Two legs of an exchange. The leg leaving [from] is negative and carries the fee;
/// the leg arriving on [to] is positive.
List<AccountTransaction> buildExchangeLegs({
  required Account from,
  required Account to,
  required int sendMinor,
  required int rateTenThousandths,
  int feeMinor = 0,
  required DateTime at,
  String? note,
  String Function()? idGenerator,
}) {
  final gen = idGenerator ?? newId;
  final pairId = gen();
  final received = convertMinor(
    sendMinor: sendMinor,
    from: from.currency,
    rateTenThousandths: rateTenThousandths,
  );
  return [
    AccountTransaction(
      id: gen(),
      accountId: from.id,
      kind: TransactionKind.exchange,
      amountMinor: -sendMinor,
      currency: from.currency,
      occurredAt: at,
      note: note,
      pairId: pairId,
      feeMinor: feeMinor > 0 ? feeMinor : null,
      rateTenThousandths: rateTenThousandths,
    ),
    AccountTransaction(
      id: gen(),
      accountId: to.id,
      kind: TransactionKind.exchange,
      amountMinor: received,
      currency: to.currency,
      occurredAt: at,
      note: note,
      pairId: pairId,
      rateTenThousandths: rateTenThousandths,
    ),
  ];
}

/// One exchange, both legs together, for the Exchange log.
class ExchangeRecord {
  const ExchangeRecord({
    required this.pairId,
    required this.outLeg,
    required this.inLeg,
  });

  final String pairId;

  /// The leg that left an account (negative amount).
  final AccountTransaction outLeg;

  /// The leg that arrived (positive amount).
  final AccountTransaction inLeg;

  DateTime get at => outLeg.occurredAt;
  Money get sent => Money(-outLeg.amountMinor, outLeg.currency);
  Money get received => Money(inLeg.amountMinor, inLeg.currency);
  Money? get fee =>
      outLeg.feeMinor == null ? null : Money(outLeg.feeMinor!, outLeg.currency);
  int? get rateTenThousandths => outLeg.rateTenThousandths;
  String? get note => outLeg.note ?? inLeg.note;

  /// Rate after the fee (see [effectiveRateTenThousandths]).
  int? get effectiveRate => effectiveRateTenThousandths(
    from: outLeg.currency,
    sendMinor: -outLeg.amountMinor,
    feeMinor: outLeg.feeMinor ?? 0,
    receivedMinor: inLeg.amountMinor,
  );
}

/// Pairs exchange legs by `pairId`. Rows without both legs are skipped. Newest first.
List<ExchangeRecord> groupExchanges(Iterable<AccountTransaction> transactions) {
  final byPair = <String, List<AccountTransaction>>{};
  for (final t in transactions) {
    if (t.kind != TransactionKind.exchange || t.pairId == null) continue;
    (byPair[t.pairId!] ??= []).add(t);
  }
  final records = <ExchangeRecord>[];
  for (final e in byPair.entries) {
    final out = e.value.where((t) => t.amountMinor < 0).firstOrNull;
    final inn = e.value.where((t) => t.amountMinor >= 0).firstOrNull;
    if (out == null || inn == null) continue;
    records.add(ExchangeRecord(pairId: e.key, outLeg: out, inLeg: inn));
  }
  records.sort((a, b) => b.at.compareTo(a.at));
  return records;
}
