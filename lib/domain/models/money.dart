/// Currencies Daftar handles. Prices are TND only; accounts may also hold USD
/// (savings in dollars, rates). Amounts are always stored as integer *minor units*.
enum Currency {
  tnd(code: 'TND', decimals: 3),
  usd(code: 'USD', decimals: 2);

  const Currency({required this.code, required this.decimals});

  final String code;

  /// TND has 1000 millimes; USD has 100 cents.
  final int decimals;

  int get unit => switch (decimals) {
    3 => 1000,
    2 => 100,
    _ => 1,
  };
}

/// An exact amount of money. Never use `double` for money in Daftar.
///
/// `Money.tnd(4400)` is 4.400 TND (4400 millimes).
class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);
  const Money.tnd(int millimes) : this(millimes, Currency.tnd);
  const Money.usd(int cents) : this(cents, Currency.usd);

  final int minor;
  final Currency currency;

  static const zeroTnd = Money.tnd(0);

  /// Parses user input like "4.400", "4,4", "12", "1 284.650".
  /// Returns null when the text is not a valid amount.
  static Money? tryParse(String input, {Currency currency = Currency.tnd}) {
    final cleaned = input
        .trim()
        .replaceAll(RegExp(r'[\s  ]'), '')
        .replaceAll(',', '.');
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(cleaned)) return null;
    final negative = cleaned.startsWith('-');
    final parts = cleaned.replaceFirst('-', '').split('.');
    final whole = int.parse(parts[0]);
    var frac = parts.length > 1 ? parts[1] : '';
    if (frac.length > currency.decimals) return null;
    frac = frac.padRight(currency.decimals, '0');
    final minor = whole * currency.unit + (frac.isEmpty ? 0 : int.parse(frac));
    return Money(negative ? -minor : minor, currency);
  }

  Money operator +(Money o) => Money(minor + _same(o).minor, currency);
  Money operator -(Money o) => Money(minor - _same(o).minor, currency);
  Money operator *(int times) => Money(minor * times, currency);

  bool get isNegative => minor < 0;

  Money _same(Money o) {
    if (o.currency != currency) {
      throw ArgumentError(
        'Currency mismatch: ${currency.code} vs ${o.currency.code}',
      );
    }
    return o;
  }

  /// "4.400", "1 284.650" (narrow no-break space between thousands), "-3.28".
  String format() {
    final abs = minor.abs();
    final whole = abs ~/ currency.unit;
    final frac = (abs % currency.unit).toString().padLeft(
      currency.decimals,
      '0',
    );
    final grouped = whole.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ' ',
    );
    return '${minor < 0 ? '-' : ''}$grouped.$frac';
  }

  /// "4.400 TND".
  String formatWithCode() => '${format()} ${currency.code}';

  @override
  int compareTo(Money other) => minor.compareTo(_same(other).minor);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => formatWithCode();
}
