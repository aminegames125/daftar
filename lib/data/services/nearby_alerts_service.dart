import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/use_cases/current_offers.dart';
import '../../domain/use_cases/nearby_alerts.dart';
import '../data_providers.dart';
import '../repositories/places_repository.dart';
import '../repositories/prices_repository.dart';
import '../repositories/products_repository.dart';
import '../repositories/saved_lists_repository.dart';
import '../repositories/settings_repository.dart';

// Nearby alerts: opt-in, off by default. Everything here
// runs on the phone; the position is read once, compared with saved places in
// memory, and thrown away. Nothing about it is stored or sent anywhere.

/// Where the settings table keeps the on/off switch and the throttle history.
abstract final class NearbyAlertKeys {
  static const enabled = 'nearby_alerts_enabled';
  static const history = 'nearby_alerts_history';
}

enum NearbyPermission { granted, denied, deniedForever, serviceOff }

/// Location permission, kept apart from reading the location so a background
/// check can never pop a permission dialog.
abstract interface class NearbyPermissionGate {
  Future<NearbyPermission> status();

  /// Shows the system dialog. Only call after the explanation screen.
  Future<NearbyPermission> request();
}

/// One coarse, cheap position. Never asks for permission; null when unknown.
abstract interface class NearbyLocationSource {
  Future<({double lat, double lng})?> position();
}

/// Shows the notification. Returns false if it could not be shown.
abstract interface class NearbyNotifier {
  Future<bool> show(NearbyAlert alert);
}

/// Runs [NearbyAlertChecker.run] about every 15+ minutes while enabled.
abstract interface class NearbyScheduler {
  Future<void> start();
  Future<void> stop();
}

/// Saved places x list prices -> the deals worth watching.
abstract interface class NearbyDealsSource {
  Future<List<NearbyDeal>> load();
}

abstract interface class NearbyHistoryStore {
  Future<NearbyAlertHistory> load();
  Future<void> save(NearbyAlertHistory history);
}

enum NearbyCheckResult {
  disabled,
  noDeals,
  throttled,
  noPermission,
  noPosition,
  nothingNearby,
  notified,
  notifyFailed,
}

/// The whole check, built only from the interfaces above so tests use fakes.
class NearbyAlertChecker {
  NearbyAlertChecker({
    required this.isEnabled,
    required this.deals,
    required this.history,
    required this.permissions,
    required this.location,
    required this.notifier,
    this.config = const NearbyAlertConfig(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<bool> Function() isEnabled;
  final NearbyDealsSource deals;
  final NearbyHistoryStore history;
  final NearbyPermissionGate permissions;
  final NearbyLocationSource location;
  final NearbyNotifier notifier;
  final NearbyAlertConfig config;
  final DateTime Function() _now;

  Future<NearbyCheckResult> run() async {
    if (!await isEnabled()) return NearbyCheckResult.disabled;
    final now = _now();
    final past = await history.load();
    final all = await deals.load();

    // Cheapest checks first: no location read when there is nothing to find.
    if (all.isEmpty) return NearbyCheckResult.noDeals;
    if (!shouldCheckLocation(
      now: now,
      history: past,
      hasDeals: true,
      config: config,
    )) {
      return NearbyCheckResult.throttled;
    }
    if (await permissions.status() != NearbyPermission.granted) {
      return NearbyCheckResult.noPermission;
    }

    final here = await location.position();
    if (here == null) return NearbyCheckResult.noPosition;

    final alert = pickNearbyAlert(
      lat: here.lat,
      lng: here.lng,
      deals: all,
      history: past,
      now: now,
      config: config,
    );
    if (alert == null) {
      await history.save(past.afterCheck(now));
      return NearbyCheckResult.nothingNearby;
    }
    if (!await notifier.show(alert)) {
      await history.save(past.afterCheck(now));
      return NearbyCheckResult.notifyFailed;
    }
    await history.save(past.afterAlert(alert.place.id, now));
    return NearbyCheckResult.notified;
  }
}

// --- Real implementations ------------------------------------------------------

class GeolocatorNearbyPermissions implements NearbyPermissionGate {
  @override
  Future<NearbyPermission> status() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return NearbyPermission.serviceOff;
      }
      return _map(await Geolocator.checkPermission());
    } catch (_) {
      return NearbyPermission.denied;
    }
  }

  @override
  Future<NearbyPermission> request() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return NearbyPermission.serviceOff;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return _map(p);
    } catch (_) {
      return NearbyPermission.denied;
    }
  }

  NearbyPermission _map(LocationPermission p) => switch (p) {
    LocationPermission.always ||
    LocationPermission.whileInUse => NearbyPermission.granted,
    LocationPermission.deniedForever => NearbyPermission.deniedForever,
    _ => NearbyPermission.denied,
  };
}

/// Battery-friendly: reuses the phone's last known fix and otherwise asks for a
/// single low-accuracy one with a short time limit.
class GeolocatorNearbyLocationSource implements NearbyLocationSource {
  @override
  Future<({double lat, double lng})?> position() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          DateTime.now().difference(last.timestamp) <
              const Duration(minutes: 10)) {
        return (lat: last.latitude, lng: last.longitude);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      return null;
    }
  }
}

/// Throttle history kept in the `settings` table (on the device only).
class SettingsNearbyHistoryStore implements NearbyHistoryStore {
  SettingsNearbyHistoryStore(this._settings);

  final SettingsRepository _settings;

  @override
  Future<NearbyAlertHistory> load() async {
    try {
      final raw = await _settings.get(NearbyAlertKeys.history);
      if (raw == null || raw.isEmpty) return const NearbyAlertHistory();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      DateTime? at(Object? v) => v is String ? DateTime.tryParse(v) : null;
      return NearbyAlertHistory(
        lastCheckAt: at(json['check']),
        lastAlertAt: at(json['alert']),
        lastAlertByPlace: {
          for (final e in ((json['places'] as Map?) ?? {}).entries)
            e.key as String: ?at(e.value),
        },
      );
    } catch (_) {
      return const NearbyAlertHistory();
    }
  }

  @override
  Future<void> save(NearbyAlertHistory h) => _settings.set(
    NearbyAlertKeys.history,
    jsonEncode({
      'check': h.lastCheckAt?.toIso8601String(),
      'alert': h.lastAlertAt?.toIso8601String(),
      'places': {
        for (final e in h.lastAlertByPlace.entries)
          e.key: e.value.toIso8601String(),
      },
    }),
  );
}

/// Reads saved lists, their priced items and the places that sell them.
class RepositoryNearbyDealsSource implements NearbyDealsSource {
  RepositoryNearbyDealsSource({
    required this.lists,
    required this.products,
    required this.prices,
    required this.places,
    this.config = const NearbyAlertConfig(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SavedListsRepository lists;
  final ProductsRepository products;
  final PricesRepository prices;
  final PlacesRepository places;
  final NearbyAlertConfig config;
  final DateTime Function() _now;

  @override
  Future<List<NearbyDeal>> load() async {
    final placeMap = {
      for (final p in await places.watchAll().first)
        if (p.lat != null && p.lng != null)
          p.id: NearbyPlace(id: p.id, name: p.name, lat: p.lat!, lng: p.lng!),
    };
    if (placeMap.isEmpty) return const [];

    final labels = <String, String>{
      for (final product in await products.watchAll().first)
        for (final v in product.variants)
          v.id: v.name == null || v.name!.isEmpty
              ? product.name
              : '${product.name} ${v.name}',
    };

    final variantIds = <String>{};
    for (final list in await lists.watchAll().first) {
      for (final item in await lists.watchItems(list.id).first) {
        if (!item.isChecked && item.variantId != null) {
          variantIds.add(item.variantId!);
        }
      }
    }

    final now = _now();
    final items = <NearbyItem>[];
    for (final id in variantIds) {
      final offers = currentOffers(
        await prices.currentOffersForVariant(id),
        now,
      );
      items.add(
        NearbyItem(
          key: id,
          label: labels[id] ?? 'An item on your list',
          quotes: {for (final o in offers) ?o.placeId: o.amount},
        ),
      );
    }
    return findNearbyDeals(items, placeMap, config: config);
  }
}

/// Placeholder until a notification/background plugin is added to the app
/// (needs pubspec + manifest changes, see PLAN). Reports that nothing was shown,
/// so the checker never records an alert that the owner did not see.
class UnavailableNearbyNotifier implements NearbyNotifier {
  @override
  Future<bool> show(NearbyAlert alert) async => false;
}

class UnavailableNearbyScheduler implements NearbyScheduler {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

// --- Providers (override in tests / when the plugins land) ---------------------

final nearbyPermissionGateProvider = Provider<NearbyPermissionGate>(
  (ref) => GeolocatorNearbyPermissions(),
);

final nearbyLocationSourceProvider = Provider<NearbyLocationSource>(
  (ref) => GeolocatorNearbyLocationSource(),
);

final nearbyNotifierProvider = Provider<NearbyNotifier>(
  (ref) => UnavailableNearbyNotifier(),
);

final nearbySchedulerProvider = Provider<NearbyScheduler>(
  (ref) => UnavailableNearbyScheduler(),
);

final nearbyAlertCheckerProvider = Provider<NearbyAlertChecker>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return NearbyAlertChecker(
    isEnabled: () async =>
        await settings.get(NearbyAlertKeys.enabled) == 'true',
    deals: RepositoryNearbyDealsSource(
      lists: ref.watch(savedListsRepositoryProvider),
      products: ref.watch(productsRepositoryProvider),
      prices: ref.watch(pricesRepositoryProvider),
      places: ref.watch(placesRepositoryProvider),
    ),
    history: SettingsNearbyHistoryStore(settings),
    permissions: ref.watch(nearbyPermissionGateProvider),
    location: ref.watch(nearbyLocationSourceProvider),
    notifier: ref.watch(nearbyNotifierProvider),
  );
});

/// The settings switch. Off by default. Turning it on is only possible after the
/// explanation screen and a granted permission (see [enable]).
final nearbyAlertsEnabledProvider =
    NotifierProvider<NearbyAlertsController, bool>(NearbyAlertsController.new);

class NearbyAlertsController extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final saved = await ref
          .read(settingsRepositoryProvider)
          .get(NearbyAlertKeys.enabled);
      if (saved == 'true' && ref.mounted) state = true;
    } catch (_) {
      // No database (bare widget test): stay off.
    }
  }

  /// Asks for permission (the caller has shown the explanation first). Turns the
  /// feature on only when granted; returns what the system answered.
  Future<NearbyPermission> enable() async {
    final result = await ref.read(nearbyPermissionGateProvider).request();
    if (result == NearbyPermission.granted) {
      await _save(true);
      await ref.read(nearbySchedulerProvider).start();
    }
    return result;
  }

  Future<void> disable() async {
    await _save(false);
    await ref.read(nearbySchedulerProvider).stop();
  }

  Future<void> _save(bool value) async {
    state = value;
    await ref
        .read(settingsRepositoryProvider)
        .set(NearbyAlertKeys.enabled, '$value');
  }
}
