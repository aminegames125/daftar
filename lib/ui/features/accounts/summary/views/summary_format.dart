import '../../../../../domain/models/money.dart';

/// What is shown instead of an amount when amounts are hidden.
const String hiddenAmountText = '••••';

/// "1 234.500 TND", "+12.00 USD" or "••••" when [hidden].
String summaryMoney(Money m, {required bool hidden, bool signed = false}) {
  if (hidden) return hiddenAmountText;
  final sign = signed && m.minor > 0 ? '+' : '';
  return '$sign${m.formatWithCode()}';
}

/// "3.1250" from a rate in ten-thousandths of a dinar.
String formatRate(int tenThousandths) {
  final whole = tenThousandths ~/ 10000;
  final frac = (tenThousandths % 10000).toString().padLeft(4, '0');
  return '$whole.$frac';
}
