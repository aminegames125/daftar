import 'package:daftar/domain/calc/calc_expression.dart';
import 'package:daftar/domain/calc/calc_keys.dart';
import 'package:flutter_test/flutter_test.dart';

int? minor(String expr) => CalcExpression.evaluate(expr)?.value?.minor;
CalcIssue? issue(String expr) => CalcExpression.evaluate(expr)?.issue;

void main() {
  group('CalcExpression', () {
    test('blank input has no result', () {
      expect(CalcExpression.evaluate(''), isNull);
      expect(CalcExpression.evaluate('  '), isNull);
      expect(CalcExpression.evaluate('+'), isNull);
    });

    test('plain numbers and decimals', () {
      expect(minor('12'), 12000);
      expect(minor('4.4'), 4400);
      expect(minor('4,400'), 4400);
      expect(minor('0.001'), 1);
      expect(minor('.5'), 500);
      expect(minor('7.'), 7000);
    });

    test('is exact where doubles are not', () {
      expect(minor('0.1+0.2'), 300);
      expect(minor('1.1×3'), 3300);
      expect(minor('4.35×100'), 435000);
      expect(minor('0.07×100'), 7000);
    });

    test('four operations and precedence', () {
      expect(minor('2+3'), 5000);
      expect(minor('10−4'), 6000);
      expect(minor('6×7'), 42000);
      expect(minor('9÷4'), 2250);
      expect(minor('2+3×4'), 14000);
      expect(minor('20−12÷4'), 17000);
      expect(minor('10-2*3/6'), 9000);
      expect(minor('2 x 3'), 6000);
    });

    test('division keeps a rational until the end, then rounds half up', () {
      expect(minor('1÷3'), 333);
      expect(minor('2÷3'), 667);
      expect(minor('10÷3×3'), 10000); // exact, no 9.999
      expect(minor('1÷8'), 125);
      expect(minor('0.001÷2'), 1); // 0.0005 rounds away from zero
      expect(minor('−0.001÷2'), -1);
    });

    test('percent', () {
      expect(minor('50%'), 500);
      expect(minor('200+10%'), 220000);
      expect(minor('200−10%'), 180000);
      expect(minor('200×10%'), 20000);
      expect(minor('200÷50%'), 400000);
      expect(minor('10+10%+10%'), 12100); // 10 → 11 → 12.1
      expect(minor('5%'), 50);
    });

    test('unary minus and negative results', () {
      expect(minor('−5+2'), -3000);
      expect(minor('5×−2'), -10000);
      expect(minor('3−5'), -2000);
      expect(minor('5−−2'), 7000);
    });

    test('a trailing operator is ignored', () {
      expect(minor('12+'), 12000);
      expect(minor('12×'), 12000);
      expect(minor('12+3×'), 15000);
    });

    test('rejects more than 3 decimals and bad input', () {
      expect(issue('1.2345'), CalcIssue.tooManyDecimals);
      expect(issue('1..2'), CalcIssue.malformed);
      expect(issue('1.2.3'), CalcIssue.malformed);
      expect(issue('2++3'), CalcIssue.malformed);
      expect(issue('×5'), CalcIssue.malformed);
      expect(issue('abc'), CalcIssue.malformed);
      expect(issue('5%5'), CalcIssue.malformed);
    });

    test('divide by zero', () {
      expect(issue('5÷0'), CalcIssue.divideByZero);
      expect(issue('5÷0.000'), CalcIssue.divideByZero);
      expect(issue('1÷(0)'), CalcIssue.malformed);
      expect(CalcExpression.evaluate('5÷0')!.issueMessage, isNotEmpty);
    });

    test('too big', () {
      expect(issue('999999999999×999999999999'), CalcIssue.tooBig);
    });

    test('result is Money in TND', () {
      expect(CalcExpression.evaluate('4.4')!.value!.format(), '4.400');
      expect(CalcExpression.evaluate('1284.65')!.value!.minor, 1284650);
    });
  });

  group('CalcEditor', () {
    String type(String keys) {
      var e = '';
      for (final ch in keys.split('')) {
        final key = CalcKey.values.firstWhere((k) => k.symbol == ch);
        e = CalcEditor.press(e, key);
      }
      return e;
    }

    test('builds numbers', () {
      expect(type('123.45'), '123.45');
      expect(type('.5'), '0.5');
      expect(type('007'), '7');
      expect(type('0.05'), '0.05');
    });

    test('one dot and at most 3 decimals per number', () {
      expect(type('1..2'), '1.2');
      expect(type('1.2345'), '1.234');
      expect(type('1.5+2.5.5'), '1.5+2.55');
    });

    test('operators replace each other and need an operand', () {
      expect(type('+5'), '5');
      expect(type('−5'), '−5');
      expect(type('5+×'), '5×');
      expect(type('5+−'), '5−');
      expect(type('5×−'), '5×−');
      expect(type('5×−+'), '5+');
      expect(type('5.+'), '5.');
    });

    test('percent only follows a number', () {
      expect(type('%'), '');
      expect(type('5%'), '5%');
      expect(type('5+%'), '5+');
      expect(type('5%3'), '5%');
    });

    test('backspace and clear', () {
      expect(CalcEditor.press('12+3', CalcKey.backspace), '12+');
      expect(CalcEditor.press('', CalcKey.backspace), '');
      expect(CalcEditor.press('12+3', CalcKey.clear), '');
    });

    test('length is capped', () {
      var e = '';
      for (var i = 0; i < 100; i++) {
        e = CalcEditor.press(e, i.isEven ? CalcKey.d1 : CalcKey.add);
      }
      expect(e.length, CalcEditor.maxLength);
    });

    test('typed expressions always evaluate or are blank', () {
      for (final keys in ['5+×3', '9÷', '1.5×2%', '−3+']) {
        final e = type(keys);
        final r = CalcExpression.evaluate(e);
        expect(r == null || r.isOk, isTrue, reason: '$keys -> $e');
      }
    });
  });
}
