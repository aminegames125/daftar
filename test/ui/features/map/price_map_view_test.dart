import 'dart:async';

import 'package:daftar/data/services/geocoding_location.dart';
import 'package:daftar/domain/models/map_pin.dart';
import 'package:daftar/ui/features/map/views/map_markers.dart';
import 'package:daftar/ui/features/map/views/price_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../core/test_app.dart';
import 'fake_map_view.dart';

class _FakeLocation implements LocationService {
  _FakeLocation(this.fix);
  final LocationFix fix;
  final gate = Completer<void>();

  @override
  Future<LocationFix> currentPosition() async {
    await gate.future;
    return fix;
  }
}

void main() {
  const best = MapPin(
    placeId: 'a',
    lat: 36.8000,
    lng: 10.1800,
    label: '3.200',
    isBest: true,
  );
  const near = MapPin(placeId: 'b', lat: 36.8001, lng: 10.1801, label: '3.500');
  const far = MapPin(
    placeId: 'c',
    lat: 36.9000,
    lng: 10.3000,
    label: '4.000',
    isStale: true,
  );

  Widget app(
    List<MapPin> pins, {
    ValueChanged<MapPin>? onTap,
    List<Override> overrides = const [],
  }) => testApp(
    PriceMapView(pins: pins, onPinTap: onTap),
    overrides: [fakeMapOverride(), ...overrides],
  );

  testWidgets('shows the price labels, no OSM attribution', (tester) async {
    await tester.pumpWidget(app([far]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('OpenStreetMap'), findsNothing);
    expect(find.text('4.000'), findsOneWidget);
  });

  testWidgets('stale pins are faded and best pins sit on top', (tester) async {
    await tester.pumpWidget(app([far, best]));
    await tester.pump(const Duration(milliseconds: 100));

    final markers = lastFakeMapConfig!.markers;
    final stale = markers.firstWhere((m) => m.id.startsWith('pin:c'));
    final top = markers.firstWhere((m) => m.id.startsWith('pin:a'));
    expect(stale.alpha, 0.4);
    expect(top.alpha, 1);
    expect(top.zIndex, greaterThan(stale.zIndex));
  });

  test('best pin: lime fill and glow; promo: amber border', () {
    const palette = MarkerPalette(
      raised: Color(0xFF111111),
      line: Color(0xFF222222),
      text: Color(0xFFEEEEEE),
      background: Color(0xFF000000),
      lime: Color(0xFFC6F432),
      onLime: Color(0xFF101010),
      amber: Color(0xFFFFB000),
    );
    final b = pricePinStyle(const PricePinVisual(best), palette);
    expect(b.fill, palette.lime);
    expect(b.glow, isTrue);
    final promo = pricePinStyle(
      const PricePinVisual(
        MapPin(placeId: 'p', lat: 0, lng: 0, label: '1.000', isPromo: true),
      ),
      palette,
    );
    expect(promo.border, palette.amber);
    expect(promo.borderWidth, 2);
    expect(promo.glow, isFalse);
    final plain = pricePinStyle(const PricePinVisual(far), palette);
    expect(plain.fill, palette.raised);
    expect(plain.border, palette.line);
  });

  testWidgets('close pins merge into a count bubble', (tester) async {
    await tester.pumpWidget(app([best, near, far]));
    await tester.pump(const Duration(milliseconds: 100));
    // best + near are ~15 m apart: one bubble "2" instead of two pills.
    expect(
      lastFakeMapConfig!.markers.where((m) => m.visual is ClusterVisual),
      hasLength(1),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3.200'), findsNothing);
    expect(find.text('4.000'), findsOneWidget);
  });

  testWidgets('tapping a pin calls onPinTap', (tester) async {
    MapPin? tapped;
    await tester.pumpWidget(app([far], onTap: (p) => tapped = p));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('4.000'));
    expect(tapped?.placeId, 'c');
  });

  testWidgets('locate me shows the radar, then the dot', (tester) async {
    final location = _FakeLocation(const LocationFix.ok(36.9, 10.3));
    await tester.pumpWidget(
      app(
        [far],
        overrides: [locationServiceProvider.overrideWithValue(location)],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.bySemanticsLabel("I'm here"));
    await tester.pump();
    expect(find.bySemanticsLabel('Finding your location'), findsOneWidget);
    location.gate.complete();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.bySemanticsLabel('Finding your location'), findsNothing);
    expect(find.bySemanticsLabel('Your location'), findsOneWidget);
  });

  testWidgets('works with reduced motion and an empty pin list', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const PriceMapView(pins: []),
        reduceMotion: true,
        dark: false,
        overrides: [fakeMapOverride()],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('default builder is test-safe (no platform view)', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const PriceMapView(pins: [])));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a cluster zooms to its members', (tester) async {
    fakeCameraCalls.clear();
    await tester.pumpWidget(app([best, near]));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('2'));
    expect(fakeCameraCalls, contains('fit:2'));
  });
}
