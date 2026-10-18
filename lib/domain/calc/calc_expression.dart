import '../models/money.dart';

/// Why an expression could not be evaluated.
enum CalcIssue { divideByZero, tooManyDecimals, tooBig, malformed }

/// The outcome of [CalcExpression.evaluate]: either a [value] or an [issue].
class CalcResult {
  const CalcResult.value(Money this.value) : issue = null;
  const CalcResult.issue(CalcIssue this.issue) : value = null;

  final Money? value;
  final CalcIssue? issue;

  bool get isOk => value != null;

  String get issueMessage => switch (issue) {
    CalcIssue.divideByZero => 'Cannot divide by zero',
    CalcIssue.tooManyDecimals => 'At most 3 decimals',
    CalcIssue.tooBig => 'Number too big',
    CalcIssue.malformed => 'Check the expression',
    null => '',
  };
}

/// Pure evaluator for the Quick calculator. Uses exact rational arithmetic
/// (BigInt numerator / denominator), never `double`, and rounds the final result
/// to whole millimes (half away from zero).
///
/// Grammar: numbers with up to 3 decimals, `+ − × ÷` (also `- * x /`), unary
/// minus, and `%`:
/// * `50%` is 0.5;
/// * `200 + 10%` is 220 (the percent applies to the left side), `200 − 10%` is 180;
/// * `200 × 10%` is 20.
///
/// Multiplication and division bind tighter than addition and subtraction.
abstract final class CalcExpression {
  /// Largest result in millimes we accept (keeps `Money` safely inside an int).
  static final BigInt _maxMinor = BigInt.from(9000000000000000); // < 2^53

  /// Evaluates [input]. A trailing operator is ignored, so a live display can
  /// show "12 + " as 12. Returns null for blank input.
  static CalcResult? evaluate(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final tokens = _tokenize(trimmed);
    if (tokens == null) return const CalcResult.issue(CalcIssue.malformed);
    if (tokens.any((t) => t.kind == _Kind.badNumber)) {
      return const CalcResult.issue(CalcIssue.tooManyDecimals);
    }
    while (tokens.isNotEmpty && tokens.last.kind == _Kind.op) {
      tokens.removeLast();
    }
    if (tokens.isEmpty) return null;
    try {
      final parser = _Parser(tokens);
      final q = parser.parse();
      final minor = q.roundedTimes(BigInt.from(Currency.tnd.unit));
      if (minor.abs() > _maxMinor) {
        return const CalcResult.issue(CalcIssue.tooBig);
      }
      return CalcResult.value(Money.tnd(minor.toInt()));
    } on _DivideByZero {
      return const CalcResult.issue(CalcIssue.divideByZero);
    } on FormatException {
      return const CalcResult.issue(CalcIssue.malformed);
    }
  }

  static List<_Token>? _tokenize(String s) {
    final out = <_Token>[];
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == ' ') {
        i++;
      } else if (_isDigit(ch) || ch == '.' || ch == ',') {
        var j = i;
        while (j < s.length && (_isDigit(s[j]) || s[j] == '.' || s[j] == ',')) {
          j++;
        }
        final text = s.substring(i, j).replaceAll(',', '.');
        final parts = text.split('.');
        if (parts.length > 2 || (parts[0].isEmpty && parts.last.isEmpty)) {
          return null;
        }
        final frac = parts.length == 2 ? parts[1] : '';
        if (frac.length > Currency.tnd.decimals) {
          out.add(const _Token(_Kind.badNumber));
        } else {
          final whole = BigInt.parse(parts[0].isEmpty ? '0' : parts[0]);
          final scale = BigInt.from(10).pow(frac.length);
          final fracInt = frac.isEmpty ? BigInt.zero : BigInt.parse(frac);
          out.add(_Token(_Kind.number, _Q(whole * scale + fracInt, scale)));
        }
        i = j;
      } else if ('+-−–'.contains(ch)) {
        out.add(_Token(_Kind.op, null, ch == '+' ? '+' : '-'));
        i++;
      } else if ('×*xX'.contains(ch)) {
        out.add(const _Token(_Kind.op, null, '*'));
        i++;
      } else if ('÷/'.contains(ch)) {
        out.add(const _Token(_Kind.op, null, '/'));
        i++;
      } else if (ch == '%') {
        out.add(const _Token(_Kind.percent));
        i++;
      } else {
        return null;
      }
    }
    return out;
  }

  static bool _isDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 0x30 && c <= 0x39;
  }
}

enum _Kind { number, op, percent, badNumber }

class _Token {
  const _Token(this.kind, [this.value, this.op]);
  final _Kind kind;
  final _Q? value;
  final String? op;
}

class _DivideByZero implements Exception {}

/// An exact fraction with a positive denominator.
class _Q {
  _Q(BigInt n, BigInt d) : n = d.isNegative ? -n : n, d = d.abs() {
    if (this.d == BigInt.zero) throw _DivideByZero();
  }

  final BigInt n;
  final BigInt d;

  _Q operator +(_Q o) => _Q(n * o.d + o.n * d, d * o.d)._reduced();
  _Q operator -(_Q o) => _Q(n * o.d - o.n * d, d * o.d)._reduced();
  _Q operator *(_Q o) => _Q(n * o.n, d * o.d)._reduced();
  _Q operator /(_Q o) => _Q(n * o.d, d * o.n)._reduced();
  _Q operator -() => _Q(-n, d);

  _Q _reduced() {
    final g = n.gcd(d);
    return g > BigInt.one ? _Q(n ~/ g, d ~/ g) : this;
  }

  /// `this * factor`, rounded half away from zero to a whole number.
  BigInt roundedTimes(BigInt factor) {
    final num = n * factor;
    final twice = num.abs() * BigInt.two + d;
    final r = twice ~/ (d * BigInt.two);
    return num.isNegative ? -r : r;
  }
}

class _Parser {
  _Parser(this._t);
  final List<_Token> _t;
  var _i = 0;

  _Token? get _peek => _i < _t.length ? _t[_i] : null;

  _Q parse() {
    final v = _expr();
    if (_i != _t.length) throw const FormatException('trailing input');
    return v;
  }

  _Q _expr() {
    var left = _term().value;
    while (_peek?.kind == _Kind.op && (_peek!.op == '+' || _peek!.op == '-')) {
      final op = _t[_i++].op!;
      final right = _term();
      // "200 + 10%" means 10% *of the left side*.
      final amount = right.percent ? left * right.value : right.value;
      left = op == '+' ? left + amount : left - amount;
    }
    return left;
  }

  ({_Q value, bool percent}) _term() {
    var cur = _unary();
    var value = cur.value;
    var percent = cur.percent;
    while (_peek?.kind == _Kind.op && (_peek!.op == '*' || _peek!.op == '/')) {
      final op = _t[_i++].op!;
      cur = _unary();
      value = op == '*' ? value * cur.value : value / cur.value;
      percent = false; // a product is no longer "a bare percentage"
    }
    return (value: value, percent: percent);
  }

  /// A number with optional leading minus and trailing `%`s. [percent] is true
  /// when it ended in `%`; [value] is then already divided by 100.
  ({_Q value, bool percent}) _unary() {
    var negative = false;
    while (_peek?.kind == _Kind.op && _peek!.op == '-') {
      negative = !negative;
      _i++;
    }
    final tok = _peek;
    if (tok == null || tok.kind != _Kind.number) {
      throw const FormatException('number expected');
    }
    _i++;
    var v = tok.value!;
    var percent = false;
    while (_peek?.kind == _Kind.percent) {
      v = v / _Q(BigInt.from(100), BigInt.one);
      percent = true;
      _i++;
    }
    return (value: negative ? -v : v, percent: percent);
  }
}
