import '../models/price_entry.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// How a price moved compared with the previous one at the same store
/// ("+12% since March", motion). Price up = coral, down = lime in the UI.
class PriceChange {
  const PriceChange({required this.percent, required this.since});

  /// Signed whole percent, never 0 (equal prices give no change).
  final int percent;

  /// When the previous price was seen.
  final DateTime since;

  bool get isUp => percent > 0;
  bool get isDown => percent < 0;

  /// "+12% since March" ("-8% since March 2025" when the year differs from [now]).
  String label(DateTime now) {
    final month = _monthNames[since.month - 1];
    final when = since.year == now.year ? month : '$month ${since.year}';
    return '${percent > 0 ? '+' : '-'}${percent.abs()}% since $when';
  }
}

/// Change from [previous] to [latest] (both at the same store), or null when the
/// price did not move. Ranges compare on their minimum, like the scorer.
PriceChange? priceChange(PriceEntry latest, PriceEntry previous) {
  final from = previous.amount.minor;
  final diff = latest.amount.minor - from;
  if (diff == 0 || from == 0) return null;
  final rounded = (diff * 100 / from).round();
  final percent = rounded == 0 ? (diff > 0 ? 1 : -1) : rounded;
  return PriceChange(percent: percent, since: previous.seenAt);
}

/// For every entry of a history, its change versus the previous entry of the
/// same place (or global type). Entries with no earlier price, or an unchanged
/// price, are absent from the map.
Map<String, PriceChange> changesByEntry(Iterable<PriceEntry> history) {
  final byStore = <String, List<PriceEntry>>{};
  for (final e in history) {
    byStore
        .putIfAbsent(e.placeId ?? 'global:${e.globalTypeId}', () => [])
        .add(e);
  }
  final result = <String, PriceChange>{};
  for (final entries in byStore.values) {
    entries.sort((a, b) => b.seenAt.compareTo(a.seenAt));
    for (var i = 0; i + 1 < entries.length; i++) {
      final change = priceChange(entries[i], entries[i + 1]);
      if (change != null) result[entries[i].id] = change;
    }
  }
  return result;
}
