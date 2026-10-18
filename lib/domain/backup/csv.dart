import '../models/money.dart';

/// RFC 4180 CSV: quotes fields containing `,` `"` or line breaks; rows end in
/// CRLF. A UTF-8 BOM is prepended so Excel reads Arabic text correctly.
String encodeCsv(List<List<String>> rows) {
  final b = StringBuffer('﻿');
  for (final row in rows) {
    b.write(row.map(_cell).join(','));
    b.write('\r\n');
  }
  return b.toString();
}

String _cell(String v) {
  if (v.contains(RegExp(r'[",\r\n]'))) return '"${v.replaceAll('"', '""')}"';
  return v;
}

/// Exact decimal for a minor-unit amount: `4400` TND -> `4.400`. No grouping,
/// no `double`, so spreadsheets parse it.
String plainAmount(int minor, Currency currency) {
  final abs = minor.abs();
  final whole = abs ~/ currency.unit;
  final frac = (abs % currency.unit).toString().padLeft(currency.decimals, '0');
  return '${minor < 0 ? '-' : ''}$whole.$frac';
}

/// Currency by stored name (`tnd`) or code (`TND`); falls back to TND.
Currency currencyFromText(String? text) {
  final t = text?.toLowerCase();
  return Currency.values.firstWhere(
    (c) => c.name == t,
    orElse: () => Currency.tnd,
  );
}

/// ISO-8601 UTC date-time for an epoch-millisecond column.
String isoFromMillis(int? ms) => ms == null
    ? ''
    : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
