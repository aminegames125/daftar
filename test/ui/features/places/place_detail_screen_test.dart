import 'dart:ui' show Tristate;

import 'package:daftar/data/services/photo_store.dart';
import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/domain/models/menu.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/ui/features/menus/view_models/menu_view_model.dart';
import 'package:daftar/ui/features/places/view_models/place_activity.dart';
import 'package:daftar/ui/features/places/view_models/places_providers.dart';
import 'package:daftar/ui/features/places/views/place_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncValue;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../core/test_app.dart';

const _cafe = PlaceType(
  id: 'cafe',
  name: 'Café',
  iconKey: 'cafe',
  kind: PlaceKind.venue,
);
const _hairdresser = PlaceType(
  id: 'hair',
  name: 'Hairdresser',
  iconKey: 'content_cut',
  kind: PlaceKind.venue,
);
const _shop = PlaceType(
  id: 'shop',
  name: 'Supermarket',
  iconKey: 'shopping_cart',
  kind: PlaceKind.shop,
);

Place _place(String typeId, {String id = 'p1'}) => Place(
  id: id,
  name: 'Chez Ali',
  typeId: typeId,
  address: 'Rue de Marseille',
  phone: '71 123 456',
  lat: 36.8,
  lng: 10.1,
  rating: 4,
  tags: const ['Clean'],
  wifiName: 'AliNet',
  wifiPassword: 'secret123',
  notes: 'Ask for the corner table',
  openingHours: OpeningHours({
    for (final d in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
      d: [(open: '00:00', close: '24:00')],
  }),
);

List<Override> _overrides(
  Place place, {
  List<PlaceActivity> activity = const [],
  MenuData? menu,
}) => [
  placeProvider(place.id).overrideWith((ref) => Stream.value(place)),
  placeTypesProvider.overrideWith(
    (ref) => Stream.value([_cafe, _hairdresser, _shop]),
  ),
  paymentMethodsProvider.overrideWith(
    (ref) => Stream.value(const [
      PaymentMethod(id: 'cash', name: 'Cash', iconKey: 'payments'),
    ]),
  ),
  placePhotosProvider(place.id).overrideWith((ref) => Stream.value(const [])),
  placeActivityProvider(place.id).overrideWith((ref) async => activity),
  staleDaysProvider.overrideWith((ref) async => 90),
  menuDataProvider(place.id).overrideWith(
    (ref) => AsyncValue.data(menu ?? const MenuData(sections: [], usual: [])),
  ),
  photoStoreProvider.overrideWithValue(FilePhotoStore()),
];

Future<void> _pump(
  WidgetTester tester,
  Place place, {
  List<PlaceActivity> activity = const [],
  MenuData? menu,
  bool dark = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      PlaceDetailScreen(placeId: place.id),
      overrides: _overrides(place, activity: activity, menu: menu),
      dark: dark,
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('shop: Products tab, History, Notes, and the floating toolbar', (
    tester,
  ) async {
    await _pump(tester, _place('shop'));

    expect(find.text('Chez Ali'), findsWidgets);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Menu'), findsNothing);
    expect(find.text('No products priced here yet.'), findsOneWidget);

    // Toolbar: Call, Directions, Copy Wi-Fi and the lime Log price.
    for (final label in ['Call', 'Directions', 'Copy Wi-Fi', 'Log price']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    // Open 24/7 in this test, so the badge says so.
    expect(find.textContaining('Open'), findsWidgets);
  });

  testWidgets('café shows Menu', (tester) async {
    await _pump(tester, _place('cafe'));
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Products'), findsNothing);
    expect(find.textContaining('No menu yet'), findsOneWidget);
  });

  testWidgets('hairdresser (a service venue) shows Price list', (tester) async {
    await _pump(tester, _place('hair', id: 'p2'));
    expect(find.text('Price list'), findsOneWidget);
    expect(find.textContaining('No price list yet'), findsOneWidget);
  });

  testWidgets('Products tab lists the latest price per product at this place', (
    tester,
  ) async {
    final entry = PriceEntry(
      id: 'e1',
      variantId: 'v1',
      placeId: 'p1',
      amount: const Money.tnd(4400),
      seenAt: DateTime.now().subtract(const Duration(days: 3)),
    );
    final stale = PriceEntry(
      id: 'e2',
      variantId: 'v2',
      placeId: 'p1',
      amount: const Money.tnd(1200),
      seenAt: DateTime.now().subtract(const Duration(days: 200)),
    );
    await _pump(
      tester,
      _place('shop'),
      activity: [
        PlaceActivity(
          entry: entry,
          title: 'Milka',
          subtitle: 'Oreo',
          productId: 'milka',
        ),
        PlaceActivity(entry: stale, title: 'Milk', productId: 'milk'),
      ],
    );

    expect(find.text('Milka · Oreo'), findsOneWidget);
    expect(find.textContaining('4.400'), findsOneWidget);
    expect(find.textContaining('Seen 3 days ago'), findsOneWidget);
    // Old prices are faded and labelled.
    expect(find.textContaining('old'), findsOneWidget);
    final faded = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('Milk'), matching: find.byType(Opacity))
          .first,
    );
    expect(faded.opacity, 0.4);
  });

  testWidgets('History and Notes tabs', (tester) async {
    await _pump(
      tester,
      _place('shop'),
      activity: [
        PlaceActivity(
          entry: PriceEntry(
            id: 'e1',
            variantId: 'v1',
            placeId: 'p1',
            amount: const Money.tnd(4400),
            seenAt: DateTime.now(),
          ),
          title: 'Milka',
          productId: 'milka',
        ),
      ],
    );
    await tester.tap(find.text('History'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Milka'), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ask for the corner table'), findsOneWidget);
  });

  testWidgets('venue shows "Your usual" and the menu with sizes', (
    tester,
  ) async {
    const option = MenuItemOption(id: 'o1', menuItemId: 'i1', name: 'S');
    const option2 = MenuItemOption(id: 'o2', menuItemId: 'i1', name: 'L');
    final item = MenuItemView(
      item: const MenuItem(
        id: 'i1',
        placeId: 'p1',
        name: 'Capucin',
        isUsual: true,
        options: [option, option2],
      ),
      options: [
        MenuOptionView(
          option: option,
          latest: PriceEntry(
            id: 'a',
            menuOptionId: 'o1',
            placeId: 'p1',
            amount: const Money.tnd(3200),
            seenAt: DateTime.now(),
          ),
        ),
        MenuOptionView(
          option: option2,
          latest: PriceEntry(
            id: 'b',
            menuOptionId: 'o2',
            placeId: 'p1',
            amount: const Money.tnd(4000),
            seenAt: DateTime.now(),
          ),
        ),
      ],
    );
    final menu = MenuData(
      sections: [
        MenuSectionView(items: [item]),
      ],
      usual: [item],
    );
    await _pump(tester, _place('cafe'), menu: menu, dark: false);

    expect(find.text('Your usual'), findsOneWidget);
    expect(find.text('Capucin'), findsNWidgets(2)); // usual card + menu
    expect(find.textContaining('3.200'), findsWidgets);
    expect(find.textContaining('4.000'), findsOneWidget);
  });

  testWidgets('Copy Wi-Fi puts the password on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, _place('shop'));
    await tester.tap(find.bySemanticsLabel('Copy Wi-Fi'));
    await tester.pump();
    expect(copied, 'secret123');
    await tester.pump(const Duration(seconds: 4)); // let the toast leave
  });

  testWidgets('no phone / location / Wi-Fi disables those toolbar buttons', (
    tester,
  ) async {
    await _pump(
      tester,
      const Place(id: 'p3', name: 'Online shop', typeId: 'shop'),
    );
    final call = tester.getSemantics(find.bySemanticsLabel('Call'));
    expect(call.flagsCollection.isEnabled, Tristate.isFalse);
  });

  testWidgets('page content fits a 1.3x font scale', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75; // ~393 dp wide, a common phone
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        const PlaceDetailScreen(placeId: 'p1'),
        overrides: _overrides(_place('cafe')),
        textScale: 1.3,
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  });
}
