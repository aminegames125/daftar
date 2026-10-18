import 'package:daftar/data/repositories/global_price_types_repository.dart';
import 'package:daftar/data/repositories/menu_repository.dart';
import 'package:daftar/data/repositories/places_repository.dart';
import 'package:daftar/data/repositories/prices_repository.dart';
import 'package:daftar/data/repositories/products_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/menu.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/domain/use_cases/search_matcher.dart';
import 'package:daftar/ui/features/search/view_models/search_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 16, 12);

void main() {
  late AppDatabase db;
  late SearchEngine engine;
  late DriftPricesRepository prices;
  late DriftProductsRepository products;
  late DriftPlacesRepository places;
  late DriftMenuRepository menu;
  final type = builtInId('place_type', 'supermarket');
  final cafeType = builtInId('place_type', 'cafe');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), () => now.toUtc());
    products = DriftProductsRepository(db, now: () => now.toUtc());
    places = DriftPlacesRepository(db, now: () => now.toUtc());
    menu = DriftMenuRepository(db, now: () => now.toUtc());
    prices = DriftPricesRepository(db, now: () => now.toUtc());
    engine = SearchEngine(
      products: products,
      places: places,
      menu: menu,
      prices: prices,
      globalTypes: DriftGlobalPriceTypesRepository(db),
    );

    await places.save(
      Place(id: 'abc', name: 'Store ABC', typeId: type, lat: 36.8, lng: 10.18),
    );
    await places.save(
      Place(id: 'cbc', name: 'Store CBC', typeId: type, lat: 36.9, lng: 10.18),
    );
    await places.save(
      Place(
        id: 'houma',
        name: 'Café El Houma',
        typeId: cafeType,
        lat: 36.81,
        lng: 10.18,
        address: 'Rue de la Liberté',
      ),
    );
    await places.save(Place(id: 'bleu', name: 'Café Bleu', typeId: cafeType));

    await products.save(
      const Product(
        id: 'milka',
        name: 'Milka',
        brand: 'Mondelez',
        variants: [
          Variant(
            id: 'oreo',
            productId: 'milka',
            name: 'Oreo',
            sizeValue: 100,
            sizeUnit: SizeUnit.g,
          ),
          Variant(
            id: 'noisette',
            productId: 'milka',
            name: 'Noisette',
            sizeValue: 100,
            sizeUnit: SizeUnit.g,
          ),
        ],
      ),
    );
    await products.save(const Product(id: 'cola', name: 'Cola'));

    Future<void> price(
      String id,
      String variant,
      String place,
      int millimes,
      int daysAgo,
    ) => prices.save(
      PriceEntry(
        id: id,
        variantId: variant,
        placeId: place,
        amount: Money.tnd(millimes),
        seenAt: now.subtract(Duration(days: daysAgo)),
      ),
    );
    await price('p1', 'oreo', 'abc', 4400, 3);
    await price('p2', 'oreo', 'cbc', 5500, 14);
    await price('p3', 'noisette', 'abc', 4900, 3);

    await menu.saveItem(
      const MenuItem(
        id: 'cap1',
        placeId: 'houma',
        name: 'Capucin',
        options: [MenuItemOption(id: 'cap1o', menuItemId: 'cap1')],
      ),
    );
    await menu.saveItem(
      const MenuItem(
        id: 'cap2',
        placeId: 'bleu',
        name: 'Cappuccino',
        options: [MenuItemOption(id: 'cap2o', menuItemId: 'cap2')],
      ),
    );
    await menu.saveItem(
      const MenuItem(
        id: 'cap3',
        placeId: 'bleu',
        name: 'Capucin',
        options: [MenuItemOption(id: 'cap3o', menuItemId: 'cap3')],
      ),
    );
    await prices.save(
      PriceEntry(
        id: 'm1',
        menuOptionId: 'cap1o',
        placeId: 'houma',
        amount: const Money.tnd(2800),
        seenAt: now,
      ),
    );
    await prices.save(
      PriceEntry(
        id: 'm2',
        menuOptionId: 'cap3o',
        placeId: 'bleu',
        amount: const Money.tnd(3200),
        seenAt: now,
      ),
    );
  });
  tearDown(() => db.close());

  Future<SearchResults> search(String q, {({double lat, double lng})? from}) =>
      engine.search(q, now: now, staleDays: 90, from: from);

  test('an empty query finds nothing', () async {
    expect((await search('   ')).isEmpty, isTrue);
  });

  test(
    'a product search compares offers of all its variants and names the best',
    () async {
      final results = await search('milka');
      final hit = (results.priced.first as ProductPriced).hit;
      expect(hit.product.id, 'milka');
      expect(hit.rank, MatchRank.exact);
      expect(hit.offerCount, 3);
      expect(hit.offers.best!.entry.id, 'p1');
      expect(hit.offers.best!.title, 'Store ABC');
      expect(hit.offers.best!.variant!.name, 'Oreo');
      expect(hit.offers.reasons.first, 'Cheapest per 100 g');
    },
  );

  test('a variant name narrows the comparison to that variant', () async {
    final results = await search('milka oreo');
    final hit = (results.priced.first as ProductPriced).hit;
    expect(hit.variants.map((v) => v.name), ['Oreo']);
    expect(hit.offerCount, 2);
  });

  test('is accent- and case-insensitive and matches token prefixes', () async {
    expect((await search('MIL')).priced, isNotEmpty);
    expect(
      (await search('cafe')).places.map((p) => p.place.id),
      containsAll(['houma', 'bleu']),
    );
    expect((await search('liberte')).places.single.place.id, 'houma');
  });

  test('a product with no prices is still found, without offers', () async {
    final hit = (await search('cola')).priced.single as ProductPriced;
    expect(hit.hit.offers.rows, isEmpty);
  });

  test('menu items are compared across venues', () async {
    final results = await search('capucin');
    final hit = results.priced.whereType<MenuPriced>().first.hit;
    expect(hit.name, 'Capucin');
    expect(hit.venueCount, 2);
    final offers = hit.groups.single.offers;
    expect(offers.rows.map((r) => r.title), ['Café El Houma', 'Café Bleu']);
    expect(offers.best!.entry.amount, const Money.tnd(2800));
  });

  test('exact matches rank before prefix matches', () async {
    final results = await search('capucin');
    final names = results.priced.map((p) => p.title).toList();
    final cappuccino = names.indexOf('Cappuccino');
    expect(
      names.indexOf('Capucin'),
      lessThan(cappuccino < 0 ? 99 : cappuccino),
    );
  });

  test(
    'place hits are listed and become map pins when they have a location',
    () async {
      final results = await search('store');
      expect(results.places.map((p) => p.place.id), ['abc', 'cbc']);
      expect(pinsForPlaces(results.places).map((p) => p.placeId), [
        'abc',
        'cbc',
      ]);
    },
  );

  test('offer pins mark the best, skip places without a location', () async {
    final results = await search('milka oreo');
    final pins = pinsForOffers(
      (results.priced.first as ProductPriced).hit.offers,
    );
    expect(pins.map((p) => p.placeId), ['abc', 'cbc']);
    expect(pins.first.isBest, isTrue);
    expect(pins.first.label, '4.400');
    expect(pins.last.isBest, isFalse);

    final bleu = await search('capucin');
    final menuPins = pinsForOffers(
      bleu.priced.whereType<MenuPriced>().first.hit.groups.single.offers,
    );
    expect(menuPins.map((p) => p.placeId), [
      'houma',
    ]); // Café Bleu has no location
  });

  test('distance shapes the winner', () async {
    // Store CBC is ~11 km away; with the user next to ABC, ABC wins by even more.
    final near = await search('milka oreo', from: (lat: 36.9, lng: 10.18));
    expect(
      (near.priced.first as ProductPriced).hit.offers.best!.title,
      'Store ABC',
    );
    expect(
      (near.priced.first as ProductPriced).hit.offers.best!.distanceKm,
      closeTo(11.1, 0.3),
    );
  });

  test('nothing found', () async {
    expect((await search('zzzz')).isEmpty, isTrue);
  });
}
