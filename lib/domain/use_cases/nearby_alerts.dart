import '../models/money.dart';
import '../place_logic/geo.dart';

/// A saved place with coordinates, as the nearby-alerts logic sees it.
class NearbyPlace {
  const NearbyPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
}

/// One thing on a saved list/basket with the current price at each place that
/// has one. [key] is a variant id or the free text; [label] is shown to the owner.
class NearbyItem {
  const NearbyItem({
    required this.key,
    required this.label,
    required this.quotes,
  });

  final String key;
  final String label;

  /// Place id -> current unit price there.
  final Map<String, Money> quotes;
}

/// A place whose price for a list item is clearly cheaper than elsewhere.
class NearbyDeal {
  const NearbyDeal({
    required this.place,
    required this.itemKey,
    required this.itemLabel,
    required this.price,
    required this.typicalPrice,
  });

  final NearbyPlace place;
  final String itemKey;
  final String itemLabel;
  final Money price;

  /// Lower median of the prices at the other places.
  final Money typicalPrice;

  Money get saving => typicalPrice - price;

  String get id => '${place.id}|$itemKey';
}

/// Tuning knobs. Defaults are conservative: few, quiet, rare alerts.
class NearbyAlertConfig {
  const NearbyAlertConfig({
    this.radiusMeters = 150,
    this.minSavingMinor = 200,
    this.minSavingPercent = 5,
    this.placeCooldown = const Duration(days: 3),
    this.minGapBetweenAlerts = const Duration(hours: 2),
    this.minCheckInterval = const Duration(minutes: 30),
    this.quietFromHour = 21,
    this.quietToHour = 8,
  });

  final double radiusMeters;

  /// A deal must save at least this many minor units (0.200 TND)...
  final int minSavingMinor;

  /// ...and at least this percent of the typical price.
  final int minSavingPercent;

  /// The same place is not announced again before this has passed.
  final Duration placeCooldown;

  /// Any two alerts are at least this far apart.
  final Duration minGapBetweenAlerts;

  /// Location is not read more often than this (battery).
  final Duration minCheckInterval;

  /// No alerts from [quietFromHour] until [quietToHour] (local, 24 h).
  final int quietFromHour;
  final int quietToHour;
}

/// What was already announced and when we last looked. Lives on the device.
class NearbyAlertHistory {
  const NearbyAlertHistory({
    this.lastCheckAt,
    this.lastAlertAt,
    this.lastAlertByPlace = const {},
  });

  final DateTime? lastCheckAt;
  final DateTime? lastAlertAt;
  final Map<String, DateTime> lastAlertByPlace;

  NearbyAlertHistory afterCheck(DateTime now) => NearbyAlertHistory(
    lastCheckAt: now,
    lastAlertAt: lastAlertAt,
    lastAlertByPlace: lastAlertByPlace,
  );

  NearbyAlertHistory afterAlert(String placeId, DateTime now) =>
      NearbyAlertHistory(
        lastCheckAt: now,
        lastAlertAt: now,
        lastAlertByPlace: {...lastAlertByPlace, placeId: now},
      );
}

/// Finds, for every list item, the places priced clearly below the typical
/// price elsewhere. Needs at least one other place to compare with and the
/// same currency. All math is on integer minor units.
List<NearbyDeal> findNearbyDeals(
  Iterable<NearbyItem> items,
  Map<String, NearbyPlace> places, {
  NearbyAlertConfig config = const NearbyAlertConfig(),
}) {
  final deals = <NearbyDeal>[];
  for (final item in items) {
    for (final MapEntry(key: placeId, value: price) in item.quotes.entries) {
      final place = places[placeId];
      if (place == null) continue;
      final others = [
        for (final MapEntry(key: id, value: m) in item.quotes.entries)
          if (id != placeId && m.currency == price.currency) m.minor,
      ]..sort();
      if (others.isEmpty) continue;
      final typical = others[(others.length - 1) ~/ 2];
      final saving = typical - price.minor;
      if (saving < config.minSavingMinor) continue;
      if (saving * 100 < typical * config.minSavingPercent) continue;
      deals.add(
        NearbyDeal(
          place: place,
          itemKey: item.key,
          itemLabel: item.label,
          price: price,
          typicalPrice: Money(typical, price.currency),
        ),
      );
    }
  }
  return deals;
}

/// What to tell the owner: one place, with its best deals (most saving first).
class NearbyAlert {
  const NearbyAlert({
    required this.place,
    required this.deals,
    required this.distanceMeters,
  });

  final NearbyPlace place;
  final List<NearbyDeal> deals;
  final double distanceMeters;

  NearbyDeal get top => deals.first;

  String get title => 'Cheaper at ${place.name}';

  /// "Milk 1L is 1.200 TND here (usually 1.500). +2 more."
  String get body {
    final more = deals.length > 1 ? ' +${deals.length - 1} more.' : '';
    return '${top.itemLabel} is ${top.price.formatWithCode()} here '
        '(usually ${top.typicalPrice.format()}).$more';
  }
}

/// True when [now] falls in the quiet window (which may wrap past midnight).
bool isQuietHour(DateTime now, NearbyAlertConfig config) {
  final h = now.hour;
  final from = config.quietFromHour;
  final to = config.quietToHour;
  if (from == to) return false;
  return from < to ? (h >= from && h < to) : (h >= from || h < to);
}

/// Cheap pre-check, before reading the location at all: skip when there is
/// nothing to alert about, it is quiet time, we looked very recently, or the
/// global gap since the last alert has not passed.
bool shouldCheckLocation({
  required DateTime now,
  required NearbyAlertHistory history,
  required bool hasDeals,
  NearbyAlertConfig config = const NearbyAlertConfig(),
}) {
  if (!hasDeals) return false;
  if (isQuietHour(now, config)) return false;
  final lastCheck = history.lastCheckAt;
  if (lastCheck != null &&
      now.difference(lastCheck) < config.minCheckInterval) {
    return false;
  }
  final lastAlert = history.lastAlertAt;
  if (lastAlert != null &&
      now.difference(lastAlert) < config.minGapBetweenAlerts) {
    return false;
  }
  return true;
}

/// Picks the alert to show for the owner's position, or null for none.
/// Only places within the radius and off cooldown count; the place with the
/// largest top saving wins (then nearest, then id for a stable result).
NearbyAlert? pickNearbyAlert({
  required double lat,
  required double lng,
  required Iterable<NearbyDeal> deals,
  required NearbyAlertHistory history,
  required DateTime now,
  NearbyAlertConfig config = const NearbyAlertConfig(),
}) {
  if (isQuietHour(now, config)) return null;
  final lastAlert = history.lastAlertAt;
  if (lastAlert != null &&
      now.difference(lastAlert) < config.minGapBetweenAlerts) {
    return null;
  }

  final byPlace = <String, List<NearbyDeal>>{};
  final distance = <String, double>{};
  for (final deal in deals) {
    final p = deal.place;
    final d = distance[p.id] ??= haversineKm(lat, lng, p.lat, p.lng) * 1000;
    if (d > config.radiusMeters) continue;
    final last = history.lastAlertByPlace[p.id];
    if (last != null && now.difference(last) < config.placeCooldown) continue;
    (byPlace[p.id] ??= []).add(deal);
  }
  if (byPlace.isEmpty) return null;

  final candidates = [
    for (final MapEntry(key: id, value: list) in byPlace.entries)
      NearbyAlert(
        place: list.first.place,
        deals: list..sort(_bySavingDesc),
        distanceMeters: distance[id]!,
      ),
  ];
  candidates.sort((a, b) {
    final bySaving = b.top.saving.minor.compareTo(a.top.saving.minor);
    if (bySaving != 0) return bySaving;
    final byDistance = a.distanceMeters.compareTo(b.distanceMeters);
    return byDistance != 0 ? byDistance : a.place.id.compareTo(b.place.id);
  });
  return candidates.first;
}

int _bySavingDesc(NearbyDeal a, NearbyDeal b) {
  final c = b.saving.minor.compareTo(a.saving.minor);
  return c != 0 ? c : a.id.compareTo(b.id);
}
