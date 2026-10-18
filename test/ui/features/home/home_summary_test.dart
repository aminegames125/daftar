import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/domain/models/menu.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/features/home/view_models/home_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const store = Place(id: 'p1', name: 'Store ABC', typeId: 't');
  const cafe = Place(id: 'p2', name: 'Café El Houma', typeId: 't');
  const milka = Product(
    id: 'milka',
    name: 'Milka',
    variants: [
      Variant(
        id: 'v-oreo',
        productId: 'milka',
        name: 'Oreo',
        sizeValue: 100,
        sizeUnit: SizeUnit.g,
      ),
      Variant(id: 'v-plain', productId: 'milka'),
    ],
  );
  const capucin = MenuItem(
    id: 'i1',
    placeId: 'p2',
    name: 'Capucin',
    options: [
      MenuItemOption(id: 'o-s', menuItemId: 'i1', name: 'S'),
      MenuItemOption(id: 'o-single', menuItemId: 'i1'),
    ],
  );
  const reference = GlobalPriceType(id: 'g1', name: 'Reference price');

  PriceEntry entry(
    String id,
    DateTime at, {
    String? variant,
    String? option,
    String? place,
    String? global,
    int minor = 4400,
    int? max,
  }) => PriceEntry(
    id: id,
    variantId: variant,
    menuOptionId: option,
    placeId: place,
    globalTypeId: global,
    amount: Money.tnd(minor),
    amountMax: max == null ? null : Money.tnd(max),
    seenAt: at,
  );

  HomeSummary build({
    List<Place> places = const [store, cafe],
    Map<String, List<MenuItem>> menus = const {
      'p2': [capucin],
    },
    Map<String, List<PriceEntry>> variants = const {},
    Map<String, List<PriceEntry>> options = const {},
  }) => buildHomeSummary(
    places: places,
    products: const [milka],
    menuItemsByPlace: menus,
    historyByVariant: variants,
    historyByOption: options,
    globalTypes: const [reference],
  );

  test('empty database gives zero counts and no latest price', () {
    final s = build(places: const [], menus: const {});
    expect(s.priceCount, 0);
    expect(s.placeCount, 0);
    expect(s.menuPlaceCount, 0);
    expect(s.latest, isNull);
    expect(s.recent, isEmpty);
  });

  test(
    'counts places, menu places (only with items) and every price entry',
    () {
      final s = build(
        menus: const {
          'p1': [],
          'p2': [capucin],
        },
        variants: {
          'v-oreo': [
            entry('a', DateTime(2026, 10, 15), variant: 'v-oreo', place: 'p1'),
            entry('b', DateTime(2026, 9, 1), variant: 'v-oreo', place: 'p1'),
          ],
        },
        options: {
          'o-s': [
            entry(
              'c',
              DateTime(2026, 10, 10),
              option: 'o-s',
              place: 'p2',
              minor: 2800,
            ),
          ],
        },
      );
      expect(s.placeCount, 2);
      expect(s.menuPlaceCount, 1);
      expect(s.priceCount, 3);
      expect(s.productCount, 1);
    },
  );

  test('latest is the newest entry across products and menus, with a readable title', () {
    final s = build(
      variants: {
        'v-oreo': [
          entry('a', DateTime(2026, 10, 10), variant: 'v-oreo', place: 'p1'),
        ],
      },
      options: {
        'o-s': [
          entry(
            'c',
            DateTime(2026, 10, 14),
            option: 'o-s',
            place: 'p2',
            minor: 2800,
          ),
        ],
      },
    );
    expect(s.latest!.id, 'c');
    expect(s.latest!.title, 'Capucin · S');
    expect(s.latest!.where, 'Café El Houma');
    expect(s.latest!.isMenu, isTrue);
    expect(s.latest!.placeId, 'p2');
    expect(s.recent.map((e) => e.id), ['c', 'a']);
    expect(s.recent.last.title, 'Milka Oreo 100 g');
    expect(s.recent.last.productId, 'milka');
  });

  test('items with a single-price option use just the item name', () {
    final s = build(
      options: {
        'o-single': [
          entry('c', DateTime(2026, 10, 14), option: 'o-single', place: 'p2'),
        ],
      },
    );
    expect(s.latest!.title, 'Capucin');
  });

  test('global prices are labelled with their type; ranges are formatted', () {
    final s = build(
      variants: {
        'v-plain': [
          entry(
            'g',
            DateTime(2026, 10, 14),
            variant: 'v-plain',
            global: 'g1',
            minor: 6000,
            max: 8000,
          ),
        ],
      },
    );
    expect(s.latest!.where, 'Global · Reference price');
    expect(s.latest!.amountText, '6.000–8.000');
    expect(s.latest!.title, 'Milka');
  });

  test('keeps only the newest five', () {
    final s = build(
      variants: {
        'v-oreo': [
          for (var i = 0; i < 8; i++)
            entry(
              'e$i',
              DateTime(2026, 10, 1 + i),
              variant: 'v-oreo',
              place: 'p1',
            ),
        ],
      },
    );
    expect(s.priceCount, 8);
    expect(s.recent, hasLength(HomeSummary.maxRecent));
    expect(s.recent.first.id, 'e7');
  });

  test('entries of unknown variants (deleted products) are ignored; unknown place is named', () {
    final s = build(
      variants: {
        'gone': [
          entry('x', DateTime(2026, 10, 1), variant: 'gone', place: 'p1'),
        ],
        'v-oreo': [
          entry(
            'y',
            DateTime(2026, 10, 2),
            variant: 'v-oreo',
            place: 'deleted-place',
          ),
        ],
      },
    );
    expect(s.priceCount, 1);
    expect(s.latest!.where, 'Unknown place');
  });

  test('sizeLabel trims whole numbers', () {
    expect(sizeLabel(100, SizeUnit.g), '100 g');
    expect(sizeLabel(1.5, SizeUnit.l), '1.5 l');
    expect(sizeLabel(6, SizeUnit.pc), '6 pc');
  });
}
