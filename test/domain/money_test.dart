import 'package:daftar/domain/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.format', () {
    test('TND uses 3 decimals', () {
      expect(const Money.tnd(4400).format(), '4.400');
      expect(const Money.tnd(15000).format(), '15.000');
      expect(const Money.tnd(5).format(), '0.005');
    });

    test('groups thousands with a narrow no-break space', () {
      expect(const Money.tnd(1284650).format(), '1 284.650');
    });

    test('USD uses 2 decimals and negatives keep the sign', () {
      expect(const Money.usd(328).format(), '3.28');
      expect(const Money.usd(-328).format(), '-3.28');
    });

    test('formatWithCode', () {
      expect(const Money.tnd(4400).formatWithCode(), '4.400 TND');
    });
  });

  group('Money.tryParse', () {
    test('accepts dot, comma, spaces and missing decimals', () {
      expect(Money.tryParse('4.400'), const Money.tnd(4400));
      expect(Money.tryParse('4,4'), const Money.tnd(4400));
      expect(Money.tryParse('12'), const Money.tnd(12000));
      expect(Money.tryParse(' 1 284.650 '), const Money.tnd(1284650));
    });

    test('rejects junk and too many decimals', () {
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('4.4001'), isNull);
      expect(Money.tryParse(''), isNull);
    });
  });

  test('arithmetic and currency safety', () {
    expect(const Money.tnd(4400) + const Money.tnd(600), const Money.tnd(5000));
    expect(const Money.tnd(4400) * 3, const Money.tnd(13200));
    expect(() => const Money.tnd(1) + const Money.usd(1), throwsArgumentError);
  });
}
