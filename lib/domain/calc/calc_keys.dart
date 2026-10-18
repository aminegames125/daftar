/// A key on the Quick calculator keypad.
enum CalcKey {
  d0('0'),
  d1('1'),
  d2('2'),
  d3('3'),
  d4('4'),
  d5('5'),
  d6('6'),
  d7('7'),
  d8('8'),
  d9('9'),
  dot('.'),
  add('+'),
  subtract('−'),
  multiply('×'),
  divide('÷'),
  percent('%'),
  backspace('⌫'),
  clear('C');

  const CalcKey(this.symbol);

  /// What the key prints (and what it appends to the expression).
  final String symbol;

  bool get isDigit => index <= d9.index;
  bool get isOperator =>
      this == add || this == subtract || this == multiply || this == divide;
}

/// Pure typing rules for the expression string, so the keypad can never build
/// something silly like `1..2`, `×5` or `0007`.
abstract final class CalcEditor {
  static const operators = '+−×÷';
  static const maxDecimals = 3;
  static const maxLength = 40;

  /// The expression after pressing [key] on [expr].
  static String press(String expr, CalcKey key) {
    switch (key) {
      case CalcKey.clear:
        return '';
      case CalcKey.backspace:
        return expr.isEmpty ? expr : expr.substring(0, expr.length - 1);
      default:
        break;
    }
    if (expr.length >= maxLength) return expr;
    final last = expr.isEmpty ? '' : expr[expr.length - 1];
    final lastIsOp = last.isNotEmpty && operators.contains(last);

    if (key.isDigit) {
      final number = _currentNumber(expr);
      if (last == '%') return expr; // "5%3" is meaningless
      if (number == '0') {
        // Replace a lone leading zero ("0" then "7" -> "7").
        return key == CalcKey.d0
            ? expr
            : expr.substring(0, expr.length - 1) + key.symbol;
      }
      final dot = number.indexOf('.');
      if (dot >= 0 && number.length - dot - 1 >= maxDecimals) return expr;
      return expr + key.symbol;
    }

    if (key == CalcKey.dot) {
      if (last == '%') return expr;
      final number = _currentNumber(expr);
      if (number.contains('.')) return expr;
      return number.isEmpty ? '${expr}0.' : '$expr.';
    }

    if (key == CalcKey.percent) {
      // Only after a digit (or another %).
      if (last.isEmpty || lastIsOp || last == '.') return expr;
      return '$expr%';
    }

    // Operators.
    if (expr.isEmpty) return key == CalcKey.subtract ? '−' : expr;
    if (last == '.') return expr;
    if (lastIsOp) {
      final before = expr.length > 1 ? expr[expr.length - 2] : '';
      // "5 × −" is allowed (negative operand); anything else replaces.
      if (key == CalcKey.subtract &&
          (last == '×' || last == '÷') &&
          before.isNotEmpty) {
        return expr + key.symbol;
      }
      if (expr.length == 1) return expr; // a lone leading minus stays
      final base =
          last == '−' && before.isNotEmpty && operators.contains(before)
          ? expr.substring(0, expr.length - 2)
          : expr.substring(0, expr.length - 1);
      return base + key.symbol;
    }
    return expr + key.symbol;
  }

  /// The digits (and dot) typed since the last operator or percent sign.
  static String _currentNumber(String expr) {
    var i = expr.length;
    while (i > 0) {
      final ch = expr[i - 1];
      if (operators.contains(ch) || ch == '%') break;
      i--;
    }
    return expr.substring(i);
  }
}
