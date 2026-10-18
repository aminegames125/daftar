import 'package:daftar/data/services/geocoding_location.dart';
import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/domain/models/map_pin.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/ui/features/map/view_models/map_places.dart';
import 'package:daftar/ui/features/map/view_models/map_price_pins.dart';
import 'package:daftar/ui/features/map/views/map_screen.dart';
import 'package:daftar/ui/features/places/view_models/places_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../core/test_app.dart';
import 'fake_map_view.dart';

class _Location implements LocationService {
  @override
  Future<LocationFix> currentPosition() async =>
      const LocationFix.ok(36.80, 10.17);
}

const _cafe = PlaceType(
  id: 'cafe',
  name: 'Café',
  iconKey: 'cafe',
  kind: PlaceKind.venue,
);
const _placeA = Place(
  id: 'a',
  name: 'Café Yasmine',
  typeId: 'cafe',
  lat: 36.8065,
  lng: 10.1815,
  rating: 5,
);
const _placeB = Place(
  id: 'b',
  name: 'Salon Nour',
  typeId: 'cafe',
  lat: 36.95,
  lng: 10.4,
);

List<Override> _overrides({List<Place> places = const [_placeA, _placeB]}) => [
  mapPlacesProvider.overrideWithValue(
    AsyncValue.data([for (final p in places) PlaceEntry(p, _cafe)]),
  ),
  locationServiceProvider.overrideWithValue(_Location()),
  fakeMapOverride(),
];

Future<void> _pump(
  WidgetTester tester, {
  List<Override>? overrides,
  bool dark = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      const MapScreen(),
      overrides: overrides ?? _overrides(),
      dark: dark,
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('shows the place count and the markers', (tester) async {
    await _pump(tester);
    expect(find.text('2 places'), findsOneWidget);
    expect(find.bySemanticsLabel('Café Yasmine'), findsOneWidget);
    expect(find.bySemanticsLabel('Salon Nour'), findsOneWidget);
    // Google draws its own logo; Daftar adds no attribution of its own.
    expect(find.textContaining('OpenStreetMap'), findsNothing);
  });

  testWidgets(
    'selecting a place opens its card; the line needs the phone position',
    (tester) async {
      await _pump(tester, dark: false);
      await tester.tap(find.bySemanticsLabel('Café Yasmine'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Show line'), findsOneWidget);

      await tester.tap(find.text('Show line'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Redraw line'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-line:route')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fake-line:route-border')),
        findsOneWidget,
      );
    },
  );

  testWidgets('price pins from search show on the map and can be cleared', (
    tester,
  ) async {
    await _pump(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapScreen)),
    );
    container.read(mapPricePinsProvider.notifier).show(const [
      MapPin(
        placeId: 'a',
        lat: 36.8065,
        lng: 10.1815,
        label: '3.200',
        isBest: true,
      ),
    ]);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('1 price pin'), findsOneWidget);
    expect(find.text('3.200'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear price pins'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('3.200'), findsNothing);
    expect(find.text('2 places'), findsOneWidget);
  });

  testWidgets('empty state, reduced motion', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        const MapScreen(),
        overrides: _overrides(places: const []),
        reduceMotion: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No places on the map yet'), findsOneWidget);
  });
}
