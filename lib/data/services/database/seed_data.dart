import '../../../domain/models/lookups.dart';

/// Starter lists (DATA_MODEL § 2). Seeded once in `onCreate`; the
/// user can rename or hide them. `iconKey` is resolved to an icon by the UI.
/// Slugs feed `builtInId`, so never change one after release.
typedef SeedPlaceType = ({
  String slug,
  String name,
  String iconKey,
  PlaceKind kind,
});
typedef SeedItem = ({String slug, String name, String iconKey});

const seedPlaceTypes = <SeedPlaceType>[
  (
    slug: 'supermarket',
    name: 'Supermarket',
    iconKey: 'shopping_cart',
    kind: PlaceKind.shop,
  ),
  (
    slug: 'grocery',
    name: 'Grocery',
    iconKey: 'storefront',
    kind: PlaceKind.shop,
  ),
  (slug: 'bakery', name: 'Bakery', iconKey: 'bakery', kind: PlaceKind.shop),
  (
    slug: 'pharmacy',
    name: 'Pharmacy',
    iconKey: 'pharmacy',
    kind: PlaceKind.shop,
  ),
  (slug: 'butcher', name: 'Butcher', iconKey: 'butcher', kind: PlaceKind.shop),
  (
    slug: 'electronics',
    name: 'Electronics',
    iconKey: 'devices',
    kind: PlaceKind.shop,
  ),
  (slug: 'cafe', name: 'Café', iconKey: 'cafe', kind: PlaceKind.venue),
  (
    slug: 'restaurant',
    name: 'Restaurant',
    iconKey: 'restaurant',
    kind: PlaceKind.venue,
  ),
  (
    slug: 'fast_food',
    name: 'Fast food',
    iconKey: 'fast_food',
    kind: PlaceKind.venue,
  ),
  (
    slug: 'hairdresser',
    name: 'Hairdresser',
    iconKey: 'content_cut',
    kind: PlaceKind.venue,
  ),
  (
    slug: 'car_wash',
    name: 'Car wash',
    iconKey: 'car_wash',
    kind: PlaceKind.venue,
  ),
  (slug: 'gym', name: 'Gym', iconKey: 'fitness', kind: PlaceKind.venue),
  (slug: 'service', name: 'Service', iconKey: 'build', kind: PlaceKind.venue),
];

const seedPaymentMethods = <SeedItem>[
  (slug: 'cash', name: 'Cash', iconKey: 'payments'),
  (slug: 'card', name: 'Card', iconKey: 'credit_card'),
  (slug: 'd17', name: 'D17', iconKey: 'wallet'),
  (slug: 'flouci', name: 'Flouci', iconKey: 'wallet'),
  (slug: 'e_dinar', name: 'e-Dinar', iconKey: 'contactless'),
  (slug: 'bank_transfer', name: 'Bank transfer', iconKey: 'account_balance'),
];

const seedCategories = <SeedItem>[
  (slug: 'food', name: 'Food', iconKey: 'restaurant'),
  (slug: 'drinks', name: 'Drinks', iconKey: 'local_drink'),
  (slug: 'snacks', name: 'Snacks', iconKey: 'cookie'),
  (slug: 'dairy', name: 'Dairy', iconKey: 'egg'),
  (slug: 'cleaning', name: 'Cleaning', iconKey: 'cleaning'),
  (slug: 'hygiene', name: 'Hygiene', iconKey: 'hygiene'),
  (slug: 'baby', name: 'Baby', iconKey: 'baby'),
  (slug: 'electronics', name: 'Electronics', iconKey: 'devices'),
  (slug: 'clothes', name: 'Clothes', iconKey: 'checkroom'),
  (slug: 'services', name: 'Services', iconKey: 'build'),
  (slug: 'transport', name: 'Transport', iconKey: 'directions_car'),
  (slug: 'other', name: 'Other', iconKey: 'category'),
];

const seedGlobalPriceTypes = <({String slug, String name})>[
  (slug: 'reference', name: 'Reference price'),
  (slug: 'seen_somewhere', name: 'Seen somewhere'),
  (slug: 'official', name: 'Official price'),
];
