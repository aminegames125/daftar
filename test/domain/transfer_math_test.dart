import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/account_balance.dart';
import 'package:daftar/domain/use_cases/transfer_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Account acc(String id, Currency c, {int opening = 0}) => Account(
    id: id,
    name: id,
    kind: AccountKind.cash,
    currency: c,
    openingBalanceMinor: opening,
  );

  final cash = acc('cash', Currency.tnd, opening: 100000);
  final d17 = acc('d17', Currency.tnd);
  final wise = acc('wise', Currency.usd, opening: 5000);
  final at = DateTime.utc(2026, 10, 17);

  group('validateTransfer', () {
    test(
      'needs two different accounts of one currency and a positive amount',
      () {
        expect(
          validateTransfer(from: null, to: d17, amountMinor: 1),
          TransferIssue.pickFrom,
        );
        expect(
          validateTransfer(from: cash, to: null, amountMinor: 1),
          TransferIssue.pickTo,
        );
        expect(
          validateTransfer(from: cash, to: cash, amountMinor: 1),
          TransferIssue.sameAccount,
        );
        expect(
          validateTransfer(from: cash, to: wise, amountMinor: 1),
          TransferIssue.currencyMismatch,
        );
        expect(
          validateTransfer(from: cash, to: d17, amountMinor: 0),
          TransferIssue.amountRequired,
        );
        expect(validateTransfer(from: cash, to: d17, amountMinor: 1), isNull);
      },
    );

    test('too little money is a warning, never a blocker', () {
      expect(
        validateTransfer(from: cash, to: d17, amountMinor: 999999999),
        isNull,
      );
      expect(isShort(balanceMinor: 100, amountMinor: 100), isFalse);
      expect(isShort(balanceMinor: 100, amountMinor: 100, feeMinor: 1), isTrue);
      expect(isShort(balanceMinor: 100, amountMinor: 101), isTrue);
    });
  });

  group('buildTransferLegs', () {
    test('two paired legs, fee only on the source', () {
      var n = 0;
      final legs = buildTransferLegs(
        from: cash,
        to: d17,
        amountMinor: 20000,
        feeMinor: 500,
        at: at,
        note: 'top up',
        idGenerator: () => 'id${n++}',
      );
      expect(legs, hasLength(2));
      final (out, inn) = (legs[0], legs[1]);
      expect(out.kind, TransactionKind.transferOut);
      expect(out.accountId, 'cash');
      expect(out.feeMinor, 500);
      expect(inn.kind, TransactionKind.transferIn);
      expect(inn.accountId, 'd17');
      expect(inn.feeMinor, isNull);
      expect(out.pairId, isNotNull);
      expect(out.pairId, inn.pairId);
      expect(out.note, 'top up');
      // Balances: source loses amount + fee, destination gains the amount.
      expect(accountBalance(cash, legs).minor, 100000 - 20000 - 500);
      expect(accountBalance(d17, legs).minor, 20000);
    });

    test('no fee means a null fee', () {
      final legs = buildTransferLegs(
        from: cash,
        to: d17,
        amountMinor: 1000,
        at: at,
      );
      expect(legs.first.feeMinor, isNull);
    });
  });

  group('exchange', () {
    test('converts TND to USD and back with half-up rounding', () {
      // 3.1250 TND per USD
      expect(
        convertMinor(
          sendMinor: 312500,
          from: Currency.tnd,
          rateTenThousandths: 31250,
        ),
        10000,
      );
      expect(
        convertMinor(
          sendMinor: 10000,
          from: Currency.usd,
          rateTenThousandths: 31250,
        ),
        312500,
      );
    });

    test('rounds half up', () {
      // 5 millimes -> 5000/31250 = 0.16 -> 0 cents
      expect(
        convertMinor(
          sendMinor: 5,
          from: Currency.tnd,
          rateTenThousandths: 31250,
        ),
        0,
      );
      // 10 millimes -> 0.32 -> 0; 16 millimes -> 0.512 -> 1
      expect(
        convertMinor(
          sendMinor: 16,
          from: Currency.tnd,
          rateTenThousandths: 31250,
        ),
        1,
      );
    });

    test(
      'both legs: signed amounts, fee on the leaving leg, shared rate and pair',
      () {
        var n = 0;
        final legs = buildExchangeLegs(
          from: cash,
          to: wise,
          sendMinor: 312500,
          rateTenThousandths: 31250,
          feeMinor: 3000,
          at: at,
          idGenerator: () => 'id${n++}',
        );
        final (out, inn) = (legs[0], legs[1]);
        expect(out.kind, TransactionKind.exchange);
        expect(out.amountMinor, -312500);
        expect(out.currency, Currency.tnd);
        expect(out.feeMinor, 3000);
        expect(inn.amountMinor, 10000);
        expect(inn.currency, Currency.usd);
        expect(inn.feeMinor, isNull);
        expect(out.rateTenThousandths, 31250);
        expect(inn.rateTenThousandths, 31250);
        expect(out.pairId, inn.pairId);
        expect(accountBalance(cash, legs).minor, 100000 - 312500 - 3000);
        expect(accountBalance(wise, legs).minor, 5000 + 10000);
      },
    );

    test('USD to TND puts the fee in USD on the dollar leg', () {
      final legs = buildExchangeLegs(
        from: wise,
        to: cash,
        sendMinor: 10000,
        rateTenThousandths: 31250,
        feeMinor: 100,
        at: at,
      );
      expect(legs[0].amountMinor, -10000);
      expect(legs[0].feeMinor, 100);
      expect(legs[1].amountMinor, 312500);
      expect(accountBalance(wise, legs).minor, 5000 - 10000 - 100);
    });

    test(
      'effective rate is the plain rate without a fee and worse with one',
      () {
        expect(
          effectiveRateTenThousandths(
            from: Currency.tnd,
            sendMinor: 312500,
            feeMinor: 0,
            receivedMinor: 10000,
          ),
          31250,
        );
        // Paying 3 TND fee on top: 315.500 TND for 100 USD = 3.1550
        expect(
          effectiveRateTenThousandths(
            from: Currency.tnd,
            sendMinor: 312500,
            feeMinor: 3000,
            receivedMinor: 10000,
          ),
          31550,
        );
        // Selling USD with a 1 USD fee: 312.500 TND for 101 USD -> lower rate.
        expect(
          effectiveRateTenThousandths(
            from: Currency.usd,
            sendMinor: 10000,
            feeMinor: 100,
            receivedMinor: 312500,
          ),
          30941,
        );
        expect(
          effectiveRateTenThousandths(
            from: Currency.tnd,
            sendMinor: 1,
            feeMinor: 0,
            receivedMinor: 0,
          ),
          isNull,
        );
      },
    );

    test(
      'validateExchange: one of each currency, amount and rate required',
      () {
        expect(
          validateExchange(
            from: cash,
            to: d17,
            amountMinor: 1,
            rateTenThousandths: 31250,
          ),
          TransferIssue.needsOneOfEach,
        );
        expect(
          validateExchange(
            from: cash,
            to: wise,
            amountMinor: 0,
            rateTenThousandths: 31250,
          ),
          TransferIssue.amountRequired,
        );
        expect(
          validateExchange(
            from: cash,
            to: wise,
            amountMinor: 1,
            rateTenThousandths: 0,
          ),
          TransferIssue.rateRequired,
        );
        expect(
          validateExchange(
            from: wise,
            to: cash,
            amountMinor: 1,
            rateTenThousandths: 31250,
          ),
          isNull,
        );
      },
    );
  });

  group('rates', () {
    test('format and parse', () {
      expect(formatRate(31250), '3.1250');
      expect(formatRate(30005), '3.0005');
      expect(parseRate('3.125'), 31250);
      expect(parseRate('3,1255'), 31255);
      expect(parseRate('3'), 30000);
      expect(parseRate('0'), isNull);
      expect(parseRate('3.12345'), isNull);
      expect(parseRate(''), isNull);
      expect(parseRate('abc'), isNull);
    });
  });

  group('groupExchanges', () {
    test(
      'pairs legs by pairId, newest first, skips lone legs and other kinds',
      () {
        final a = buildExchangeLegs(
          from: cash,
          to: wise,
          sendMinor: 312500,
          rateTenThousandths: 31250,
          feeMinor: 3000,
          at: DateTime.utc(2026, 10, 1),
        );
        final b = buildExchangeLegs(
          from: wise,
          to: cash,
          sendMinor: 1000,
          rateTenThousandths: 31000,
          at: DateTime.utc(2026, 10, 5),
        );
        final transfer = buildTransferLegs(
          from: cash,
          to: d17,
          amountMinor: 1,
          at: at,
        );
        final records = groupExchanges([
          ...a,
          ...transfer,
          b.first,
          ...b.skip(1),
        ]);
        expect(records, hasLength(2));
        expect(records.first.sent, const Money.usd(1000));
        expect(records.first.received, const Money.tnd(31000));
        expect(records.last.sent, const Money.tnd(312500));
        expect(records.last.fee, const Money.tnd(3000));
        expect(records.last.effectiveRate, 31550);
        expect(groupExchanges([a.first]), isEmpty);
      },
    );
  });
}
