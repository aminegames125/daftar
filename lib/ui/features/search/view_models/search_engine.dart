import 'package:collection/collection.dart';

import '../../../../data/repositories/global_price_types_repository.dart';
import '../../../../data/repositories/menu_repository.dart';
import '../../../../data/repositories/places_repository.dart';
import '../../../../data/repositories/prices_repository.dart';
import '../../../../data/repositories/products_repository.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/map_pin.dart';
import '../../../../domain/models/menu.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/search/normalize_for_search.dart';
import '../../../../domain/use_cases/best_offer_scorer.dart';
import '../../../../domain/use_cases/search_matcher.dart';
import '../../products/view_models/offer_rows.dart';

/// How many product / menu matches get their prices scored (the rest are listed
/// by name only) so a one-letter query stays fast.
const int kMaxScoredHits = 12;

/// A product (with all or the matching variants) and where it is cheapest.
class ProductHit {
  const ProductHit({
    required this.product,
    required this.variants,
    required this.rank,
    required this.offers,
  });

  final Product product;

  /// The variants whose prices were compared.
  final List<Variant> variants;
  final MatchRank rank;

  /// Empty when no price was logged yet.
  final OffersView offers;

  int get offerCount => offers.rows.length;

  String get title => product.name;
}

/// The offers for one option of a menu item ("S", "L", or the single price).
class MenuOptionGroup {
  const MenuOptionGroup({required this.label, required this.offers});

  /// null = the single price.
  final String? label;
  final OffersView offers;
}

/// A menu item name found at one or more venues ("Capucin" at every café).
class MenuHit {
  const MenuHit({
    required this.name,
    required this.rank,
    required this.venueCount,
    required this.groups,
  });

  final String name;
  final MatchRank rank;
  final int venueCount;

  /// Biggest group (most venues) first.
  final List<MenuOptionGroup> groups;

  String get title => name;
}

class PlaceHit {
  const PlaceHit({required this.place, required this.rank});

  final Place place;
  final MatchRank rank;
}

/// Something with prices to compare: a product or a menu item.
sealed class PricedHit {
  const PricedHit();

  String get title;
  MatchRank get rank;
}

class ProductPriced extends PricedHit {
  const ProductPriced(this.hit);
  final ProductHit hit;

  @override
  String get title => hit.title;

  @override
  MatchRank get rank => hit.rank;
}

class MenuPriced extends PricedHit {
  const MenuPriced(this.hit);
  final MenuHit hit;

  @override
  String get title => hit.title;

  @override
  MatchRank get rank => hit.rank;
}

class SearchResults {
  const SearchResults({
    required this.query,
    this.priced = const [],
    this.places = const [],
  });

  final String query;

  /// Products and menu items, best match first.
  final List<PricedHit> priced;
  final List<PlaceHit> places;

  bool get isEmpty => priced.isEmpty && places.isEmpty;
  static const none = SearchResults(query: '');
}

/// Pins for the map: one per place with a logged price for [hit]; best glows.
List<MapPin> pinsForOffers(OffersView offers) {
  return [
    for (final row in offers.rows)
      if (row.place != null && row.place!.hasLocation)
        MapPin(
          placeId: row.place!.id,
          lat: row.place!.lat!,
          lng: row.place!.lng!,
          label: row.entry.amount.format(),
          isBest: row.isBest,
          isStale: row.isStale,
          isPromo: row.entry.isPromo,
        ),
  ];
}

List<MapPin> pinsForPlaces(Iterable<PlaceHit> hits) => [
  for (final h in hits)
    if (h.place.hasLocation)
      MapPin(
        placeId: h.place.id,
        lat: h.place.lat!,
        lng: h.place.lng!,
        label: h.place.name,
      ),
];

/// Searches products, variants, menu items and places (normalised, token-prefix,
/// ranked exact > prefix > contains, see DATA_MODEL § 6) and scores the prices of
/// what it found (DATA_MODEL § 7). Data is small, so it filters in memory.
class SearchEngine {
  SearchEngine({
    required this.products,
    required this.places,
    required this.menu,
    required this.prices,
    required this.globalTypes,
  });

  final ProductsRepository products;
  final PlacesRepository places;
  final MenuRepository menu;
  final PricesRepository prices;
  final GlobalPriceTypesRepository globalTypes;

  Future<SearchResults> search(
    String raw, {
    required DateTime now,
    required int staleDays,
    GeoPoint? from,
  }) async {
    final q = SearchQuery(raw);
    if (q.isEmpty) return SearchResults.none;

    final allPlaces = await places.watchAll().first;
    final placeMap = {for (final p in allPlaces) p.id: p};
    final typeMap = {
      for (final t in await globalTypes.watchAll().first) t.id: t,
    };

    final productHits = await _products(
      q,
      placeMap,
      typeMap,
      now,
      staleDays,
      from,
    );
    final menuHits = await _menu(
      q,
      allPlaces,
      placeMap,
      typeMap,
      now,
      staleDays,
      from,
    );
    final placeHits = _places(q, allPlaces);

    final priced = <PricedHit>[
      for (final h in productHits) ProductPriced(h),
      for (final h in menuHits) MenuPriced(h),
    ]..sort(_comparePriced);

    return SearchResults(query: raw.trim(), priced: priced, places: placeHits);
  }

  /// Better match first; among equal matches those with prices, then A→Z.
  int _comparePriced(PricedHit a, PricedHit b) {
    final byRank = a.rank.index.compareTo(b.rank.index);
    if (byRank != 0) return byRank;
    final byPrices = (_hasOffers(b) ? 1 : 0).compareTo(_hasOffers(a) ? 1 : 0);
    if (byPrices != 0) return byPrices;
    return normalizeForSearch(a.title).compareTo(normalizeForSearch(b.title));
  }

  bool _hasOffers(PricedHit h) => switch (h) {
    ProductPriced(:final hit) => hit.offers.rows.isNotEmpty,
    MenuPriced(:final hit) => hit.groups.any((g) => g.offers.rows.isNotEmpty),
  };

  Future<List<ProductHit>> _products(
    SearchQuery q,
    Map<String, Place> placeMap,
    Map<String, GlobalPriceType> typeMap,
    DateTime now,
    int staleDays,
    GeoPoint? from,
  ) async {
    final matches = <(Product, List<Variant>, MatchRank)>[];
    for (final p in await products.watchAll().first) {
      final nameRank = q.matchAny([
        normalizeForSearch(p.name),
        normalizeForSearch('${p.name} ${p.brand ?? ''}'),
      ]);
      if (nameRank != null) {
        matches.add((p, p.variants, nameRank));
        continue;
      }
      // Matches only through a variant ("milka oreo", a barcode): compare just those.
      final byVariant = <Variant, MatchRank>{};
      for (final v in p.variants) {
        final rank = q.match(
          normalizeForSearch(
            '${p.name} ${p.brand ?? ''} ${v.name ?? ''} ${v.barcode ?? ''}',
          ),
        );
        if (rank != null) byVariant[v] = rank;
      }
      if (byVariant.isEmpty) continue;
      final best = byVariant.values.reduce(
        (a, b) => a.index <= b.index ? a : b,
      );
      matches.add((p, byVariant.keys.toList(), best));
    }
    matches.sort((a, b) {
      final byRank = a.$3.index.compareTo(b.$3.index);
      return byRank != 0
          ? byRank
          : normalizeForSearch(a.$1.name)
                .compareTo(normalizeForSearch(b.$1.name));
    });

    final hits = <ProductHit>[];
    for (final (index, (product, variants, rank)) in matches.indexed) {
      var offers = OffersView.empty;
      if (index < kMaxScoredHits) {
        final byVariant = <Variant, List<PriceEntry>>{
          for (final v in variants)
            v: await prices.currentOffersForVariant(v.id),
        };
        offers = buildMultiVariantOffersView(
          historyByVariant: byVariant,
          places: placeMap,
          types: typeMap,
          now: now,
          staleDays: staleDays,
          from: from,
        );
      }
      hits.add(
        ProductHit(
          product: product,
          variants: variants,
          rank: rank,
          offers: offers,
        ),
      );
    }
    return hits;
  }

  Future<List<MenuHit>> _menu(
    SearchQuery q,
    List<Place> allPlaces,
    Map<String, Place> placeMap,
    Map<String, GlobalPriceType> typeMap,
    DateTime now,
    int staleDays,
    GeoPoint? from,
  ) async {
    final byName = <String, List<MenuItem>>{};
    final ranks = <String, MatchRank>{};
    for (final place in allPlaces) {
      for (final item in await menu.watchItems(place.id).first) {
        final key = normalizeForSearch(item.name);
        final rank = q.match(key);
        if (rank == null) continue;
        byName.putIfAbsent(key, () => []).add(item);
        ranks[key] = rank;
      }
    }

    final keys = byName.keys.toList()
      ..sort((a, b) {
        final byRank = ranks[a]!.index.compareTo(ranks[b]!.index);
        return byRank != 0 ? byRank : a.compareTo(b);
      });

    final hits = <MenuHit>[];
    for (final (index, key) in keys.indexed) {
      final items = byName[key]!;
      final groups = <MenuOptionGroup>[];
      if (index < kMaxScoredHits) {
        // Same option label across venues are comparable (S with S, the single price with the single price).
        final byOption = <String, List<PriceEntry>>{};
        final labels = <String, String?>{};
        for (final item in items) {
          for (final option in item.options) {
            final optionKey = normalizeForSearch(option.name ?? '');
            labels.putIfAbsent(optionKey, () => option.name);
            byOption
                .putIfAbsent(optionKey, () => [])
                .addAll(await prices.currentOffersForMenuOption(option.id));
          }
        }
        for (final entry in byOption.entries) {
          final offers = buildMenuOffersView(
            entries: entry.value,
            places: placeMap,
            types: typeMap,
            now: now,
            staleDays: staleDays,
            from: from,
          );
          if (offers.rows.isNotEmpty) {
            groups.add(
              MenuOptionGroup(label: labels[entry.key], offers: offers),
            );
          }
        }
        groups.sort(
          (a, b) => b.offers.rows.length.compareTo(a.offers.rows.length),
        );
      }
      hits.add(
        MenuHit(
          name: items.first.name,
          rank: ranks[key]!,
          venueCount: items.map((i) => i.placeId).toSet().length,
          groups: groups,
        ),
      );
    }
    return hits;
  }

  List<PlaceHit> _places(SearchQuery q, List<Place> allPlaces) {
    final hits = <PlaceHit>[];
    for (final place in allPlaces) {
      final rank = q.matchAny([
        normalizeForSearch(place.name),
        normalizeForSearch(
          '${place.name} ${place.address ?? ''} ${place.tags.join(' ')}',
        ),
      ]);
      if (rank != null) hits.add(PlaceHit(place: place, rank: rank));
    }
    return hits.sorted((a, b) {
      final byRank = a.rank.index.compareTo(b.rank.index);
      return byRank != 0
          ? byRank
          : normalizeForSearch(a.place.name)
                .compareTo(normalizeForSearch(b.place.name));
    });
  }
}
