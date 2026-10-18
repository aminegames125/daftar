import 'package:daftar/data/services/nearby_alerts_service.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/nearby_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

const _shop = NearbyPlace(
  id: 'a',
  name: 'Carrefour',
  lat: 36.8000,
  lng: 10.1800,
);
const _far = NearbyPlace(id: 'b', name: 'Mg', lat: 36.9000, lng: 10.3000);

// About 55 m north of _shop.
const _nearLat = 36.8005;
const _nearLng = 10.1800;

final _noon = DateTime(2026, 10, 18, 12);

NearbyDeal _deal(NearbyPlace p, String key, int price, int typical) =>
    NearbyDeal(
      place: p,
      itemKey: key,
      itemLabel: key,
      price: Money.tnd(price),
      typicalPrice: Money.tnd(typical),
    );

void main() {
  group('findNearbyDeals', () {
    final places = {'a': _shop, 'b': _far};

    test('flags the place that is clearly cheaper than the typical price', () {
      final deals = findNearbyDeals([
        const NearbyItem(
          key: 'milk',
          label: 'Milk',
          quotes: {'a': Money.tnd(1200), 'b': Money.tnd(1500)},
        ),
      ], places);
      expect(deals, hasLength(1));
      expect(deals.single.place.id, 'a');
      expect(deals.single.saving.minor, 300);
    });

    test('ignores tiny savings and items with a single price', () {
      final deals = findNearbyDeals([
        const NearbyItem(
          key: 'a',
          label: 'A',
          quotes: {'a': Money.tnd(1400), 'b': Money.tnd(1500)},
        ),
        const NearbyItem(key: 'b', label: 'B', quotes: {'a': Money.tnd(100)}),
      ], places);
      expect(deals, isEmpty);
    });

    test('ignores places without coordinates and other currencies', () {
      final deals = findNearbyDeals([
        const NearbyItem(
          key: 'x',
          label: 'X',
          quotes: {
            'a': Money.tnd(1000),
            'zz': Money.tnd(100),
            'b': Money.usd(9999),
          },
        ),
      ], places);
      expect(deals, isEmpty);
    });
  });

  group('quiet hours', () {
    const config = NearbyAlertConfig();
    test('wrap past midnight', () {
      expect(isQuietHour(DateTime(2026, 1, 1, 23), config), isTrue);
      expect(isQuietHour(DateTime(2026, 1, 1, 3), config), isTrue);
      expect(isQuietHour(DateTime(2026, 1, 1, 8), config), isFalse);
      expect(isQuietHour(DateTime(2026, 1, 1, 20), config), isFalse);
    });
  });

  group('shouldCheckLocation', () {
    test('false without deals, at night, or just after a check or alert', () {
      const none = NearbyAlertHistory();
      expect(
        shouldCheckLocation(now: _noon, history: none, hasDeals: false),
        isFalse,
      );
      expect(
        shouldCheckLocation(
          now: DateTime(2026, 10, 18, 23),
          history: none,
          hasDeals: true,
        ),
        isFalse,
      );
      expect(
        shouldCheckLocation(
          now: _noon,
          history: NearbyAlertHistory(
            lastCheckAt: _noon.subtract(const Duration(minutes: 10)),
          ),
          hasDeals: true,
        ),
        isFalse,
      );
      expect(
        shouldCheckLocation(
          now: _noon,
          history: NearbyAlertHistory(
            lastAlertAt: _noon.subtract(const Duration(minutes: 90)),
          ),
          hasDeals: true,
        ),
        isFalse,
      );
    });

    test('true when everything allows it', () {
      expect(
        shouldCheckLocation(
          now: _noon,
          history: NearbyAlertHistory(
            lastCheckAt: _noon.subtract(const Duration(hours: 1)),
          ),
          hasDeals: true,
        ),
        isTrue,
      );
    });
  });

  group('pickNearbyAlert', () {
    final deals = [
      _deal(_shop, 'milk', 1200, 1500),
      _deal(_shop, 'oil', 3000, 3900),
      _deal(_far, 'milk', 1000, 1500),
    ];

    NearbyAlert? pick({NearbyAlertHistory? history, DateTime? now}) =>
        pickNearbyAlert(
          lat: _nearLat,
          lng: _nearLng,
          deals: deals,
          history: history ?? const NearbyAlertHistory(),
          now: now ?? _noon,
        );

    test('shows the place within the radius, best saving first', () {
      final alert = pick()!;
      expect(alert.place.id, 'a');
      expect(alert.top.itemKey, 'oil');
      expect(alert.deals, hasLength(2));
      expect(alert.distanceMeters, lessThan(100));
      expect(alert.title, 'Cheaper at Carrefour');
      expect(alert.body, contains('3.000 TND'));
      expect(alert.body, contains('+1 more'));
    });

    test('nothing when out of range', () {
      expect(
        pickNearbyAlert(
          lat: 35.0,
          lng: 9.0,
          deals: deals,
          history: const NearbyAlertHistory(),
          now: _noon,
        ),
        isNull,
      );
    });

    test('respects the per-place cooldown, then allows it again', () {
      final history = NearbyAlertHistory(
        lastAlertAt: _noon.subtract(const Duration(hours: 5)),
        lastAlertByPlace: {'a': _noon.subtract(const Duration(days: 1))},
      );
      expect(pick(history: history), isNull);
      expect(
        pick(history: history, now: _noon.add(const Duration(days: 3))),
        isNotNull,
      );
    });

    test('respects the global gap and quiet hours', () {
      final recent = NearbyAlertHistory(
        lastAlertAt: _noon.subtract(const Duration(minutes: 30)),
      );
      expect(pick(history: recent), isNull);
      expect(pick(now: DateTime(2026, 10, 18, 22)), isNull);
    });
  });

  group('NearbyAlertChecker', () {
    late _FakeHistory history;
    late _FakeNotifier notifier;
    late _FakeLocation location;
    late _FakePermissions permissions;
    late List<NearbyDeal> deals;
    var enabled = true;

    NearbyAlertChecker build() => NearbyAlertChecker(
      isEnabled: () async => enabled,
      deals: _FakeDeals(() => deals),
      history: history,
      permissions: permissions,
      location: location,
      notifier: notifier,
      now: () => _noon,
    );

    setUp(() {
      enabled = true;
      history = _FakeHistory();
      notifier = _FakeNotifier();
      location = _FakeLocation((lat: _nearLat, lng: _nearLng));
      permissions = _FakePermissions(NearbyPermission.granted);
      deals = [_deal(_shop, 'milk', 1200, 1500)];
    });

    test('off by default means no location read at all', () async {
      enabled = false;
      expect(await build().run(), NearbyCheckResult.disabled);
      expect(location.reads, 0);
    });

    test('no deals: does not read the location', () async {
      deals = [];
      expect(await build().run(), NearbyCheckResult.noDeals);
      expect(location.reads, 0);
    });

    test('no permission: does not read the location', () async {
      permissions = _FakePermissions(NearbyPermission.denied);
      expect(await build().run(), NearbyCheckResult.noPermission);
      expect(location.reads, 0);
    });

    test('notifies once, then is throttled', () async {
      final checker = build();
      expect(await checker.run(), NearbyCheckResult.notified);
      expect(notifier.shown, hasLength(1));
      expect(await checker.run(), NearbyCheckResult.throttled);
      expect(notifier.shown, hasLength(1));
      expect(location.reads, 1);
    });

    test('far away: records the check but does not notify', () async {
      location = _FakeLocation((lat: 35.0, lng: 9.0));
      expect(await build().run(), NearbyCheckResult.nothingNearby);
      expect(notifier.shown, isEmpty);
      expect(history.value.lastCheckAt, _noon);
      expect(history.value.lastAlertAt, isNull);
    });

    test('a failed notification is not recorded as shown', () async {
      notifier.ok = false;
      expect(await build().run(), NearbyCheckResult.notifyFailed);
      expect(history.value.lastAlertAt, isNull);
    });

    test('unknown position', () async {
      location = _FakeLocation(null);
      expect(await build().run(), NearbyCheckResult.noPosition);
    });
  });
}

class _FakeHistory implements NearbyHistoryStore {
  NearbyAlertHistory value = const NearbyAlertHistory();
  @override
  Future<NearbyAlertHistory> load() async => value;
  @override
  Future<void> save(NearbyAlertHistory history) async => value = history;
}

class _FakeNotifier implements NearbyNotifier {
  final shown = <NearbyAlert>[];
  bool ok = true;
  @override
  Future<bool> show(NearbyAlert alert) async {
    if (ok) shown.add(alert);
    return ok;
  }
}

class _FakeLocation implements NearbyLocationSource {
  _FakeLocation(this.fix);
  final ({double lat, double lng})? fix;
  int reads = 0;
  @override
  Future<({double lat, double lng})?> position() async {
    reads++;
    return fix;
  }
}

class _FakePermissions implements NearbyPermissionGate {
  _FakePermissions(this.value);
  final NearbyPermission value;
  @override
  Future<NearbyPermission> status() async => value;
  @override
  Future<NearbyPermission> request() async => value;
}

class _FakeDeals implements NearbyDealsSource {
  _FakeDeals(this._get);
  final List<NearbyDeal> Function() _get;
  @override
  Future<List<NearbyDeal>> load() async => _get();
}
