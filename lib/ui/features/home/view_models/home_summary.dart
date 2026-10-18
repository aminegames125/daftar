import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/menu.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/product.dart';

/// One line of the Home "Recent" list and the "Latest" caption of the Prices card.
class RecentPrice {
  const RecentPrice({
    required this.id,
    required this.title,
    required this.where,
    required this.amount,
    this.amountMax,
    required this.seenAt,
    this.productId,
    this.placeId,
    required this.isMenu,
  });

  final String id;

  /// "Milka Oreo 100 g", "Capucin · L".
  final String title;

  /// Place name, or "Global · Reference price".
  final String where;
  final Money amount;
  final Money? amountMax;
  final DateTime seenAt;

  /// Set for product prices (opens the product page).
  final String? productId;

  /// Set for place prices and menu items (opens the place page).
  final String? placeId;
  final bool isMenu;

  /// "4.400" or "6.000–8.000".
  String get amountText => amountMax == null
      ? amount.format()
      : '${amount.format()}–${amountMax!.format()}';
}

/// Everything Home shows, derived from the database.
class HomeSummary {
  const HomeSummary({
    this.priceCount = 0,
    this.placeCount = 0,
    this.menuPlaceCount = 0,
    this.productCount = 0,
    this.recent = const [],
  });

  /// Logged price entries (products and menu items).
  final int priceCount;
  final int placeCount;

  /// Places that have at least one menu item.
  final int menuPlaceCount;
  final int productCount;

  /// Newest first, at most [maxRecent].
  final List<RecentPrice> recent;

  RecentPrice? get latest => recent.isEmpty ? null : recent.first;

  static const int maxRecent = 5;
}

/// "100 g", "1.5 l", "6 pc".
String sizeLabel(double value, SizeUnit unit) {
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  return '$text ${unit.name}';
}

/// Pure builder behind `homeSummaryProvider`; unit tested.
///
/// [historyByVariant] / [historyByOption] hold every price entry of a variant /
/// menu option; [menuItemsByPlace] the menu items of each place.
HomeSummary buildHomeSummary({
  required List<Place> places,
  required List<Product> products,
  required Map<String, List<MenuItem>> menuItemsByPlace,
  required Map<String, List<PriceEntry>> historyByVariant,
  required Map<String, List<PriceEntry>> historyByOption,
  required List<GlobalPriceType> globalTypes,
}) {
  final placeById = {for (final p in places) p.id: p};
  final typeById = {for (final t in globalTypes) t.id: t};
  final productByVariant = <String, (Product, Variant)>{
    for (final p in products)
      for (final v in p.variants) v.id: (p, v),
  };
  final itemByOption = <String, (MenuItem, MenuItemOption)>{
    for (final items in menuItemsByPlace.values)
      for (final item in items)
        for (final o in item.options) o.id: (item, o),
  };

  String whereOf(PriceEntry e) {
    final placeId = e.placeId;
    if (placeId == null) {
      final type = typeById[e.globalTypeId];
      return type == null ? 'Global' : 'Global · ${type.name}';
    }
    return placeById[placeId]?.name ?? 'Unknown place';
  }

  var priceCount = 0;
  final all = <RecentPrice>[];

  for (final MapEntry(key: variantId, value: entries)
      in historyByVariant.entries) {
    final owner = productByVariant[variantId];
    if (owner == null) continue;
    final (product, variant) = owner;
    final parts = [
      product.name,
      if (variant.name != null && variant.name!.isNotEmpty) variant.name!,
      if (variant.sizeValue != null && variant.sizeUnit != null)
        sizeLabel(variant.sizeValue!, variant.sizeUnit!),
    ];
    for (final e in entries) {
      priceCount++;
      all.add(
        RecentPrice(
          id: e.id,
          title: parts.join(' '),
          where: whereOf(e),
          amount: e.amount,
          amountMax: e.amountMax,
          seenAt: e.seenAt,
          productId: product.id,
          placeId: e.placeId,
          isMenu: false,
        ),
      );
    }
  }

  for (final MapEntry(key: optionId, value: entries)
      in historyByOption.entries) {
    final owner = itemByOption[optionId];
    if (owner == null) continue;
    final (item, option) = owner;
    final title = option.name == null || option.name!.isEmpty
        ? item.name
        : '${item.name} · ${option.name}';
    for (final e in entries) {
      priceCount++;
      all.add(
        RecentPrice(
          id: e.id,
          title: title,
          where: whereOf(e),
          amount: e.amount,
          amountMax: e.amountMax,
          seenAt: e.seenAt,
          placeId: e.placeId ?? item.placeId,
          isMenu: true,
        ),
      );
    }
  }

  all.sort((a, b) => b.seenAt.compareTo(a.seenAt));

  return HomeSummary(
    priceCount: priceCount,
    placeCount: places.length,
    menuPlaceCount: menuItemsByPlace.values
        .where((items) => items.isNotEmpty)
        .length,
    productCount: products.length,
    recent: all.take(HomeSummary.maxRecent).toList(),
  );
}
