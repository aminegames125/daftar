import '../models/price_entry.dart';

/// Reduces a price history to what is *current* (DATA_MODEL § 2 notes): the
/// newest entry per place (or per global type), ignoring expired promos, so an
/// expired promo falls back to the newest regular price before it.
List<PriceEntry> currentOffers(Iterable<PriceEntry> history, DateTime now) {
  final newestFirst = history.where((e) => !e.isExpiredAt(now)).toList()
    ..sort((a, b) => b.seenAt.compareTo(a.seenAt));
  final seen = <String>{};
  return [
    for (final entry in newestFirst)
      if (seen.add(entry.placeId ?? 'global:${entry.globalTypeId}')) entry,
  ];
}
