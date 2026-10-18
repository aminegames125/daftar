import 'money.dart';

/// One line of a [Basket]: something to buy, its unit price and how many.
///
/// [productId] / [variantId] are set when the line came from the catalog (so
/// Best store can look the item up at other places); they are null for a line
/// typed by hand.
class BasketItem {
  const BasketItem({
    required this.id,
    required this.name,
    required this.unitPrice,
    this.quantity = 1,
    this.productId,
    this.variantId,
  });

  /// Stable id of this line inside the basket (not a database id).
  final String id;
  final String name;
  final Money unitPrice;
  final int quantity;
  final String? productId;
  final String? variantId;

  /// `unitPrice × quantity`.
  Money get lineTotal => unitPrice * quantity;

  bool get isFromCatalog => productId != null;

  BasketItem copyWith({String? name, Money? unitPrice, int? quantity}) =>
      BasketItem(
        id: id,
        name: name ?? this.name,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
        productId: productId,
        variantId: variantId,
      );
}

/// A shopping basket: items × quantity, optionally at a chosen place. Immutable;
/// every change returns a new basket. Pure logic, shared by the Basket, Best store
/// and Split modes.
class Basket {
  const Basket({this.items = const [], this.placeId, this.placeName});

  static const int maxQuantity = 99;

  final List<BasketItem> items;

  /// The place whose prices the basket is priced at (null = no place chosen).
  final String? placeId;
  final String? placeName;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  /// Number of lines.
  int get lineCount => items.length;

  /// Total units (sum of quantities); what the badge shows.
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  /// Sum of every line total.
  Money get total => items.fold(Money.zeroTnd, (sum, i) => sum + i.lineTotal);

  /// Adds [item]. A catalog line with the same variant (or product) and unit
  /// price, or a typed line with the same name (ignoring case) and price, is
  /// merged by adding quantities instead of duplicating the line.
  Basket add(BasketItem item) {
    final i = items.indexWhere((e) => _sameLine(e, item));
    if (i < 0) return _with([...items, item]);
    final merged = items[i].copyWith(
      quantity: _clamp(items[i].quantity + item.quantity),
    );
    return _with([...items]..[i] = merged);
  }

  /// Sets a line's quantity; zero or less removes it.
  Basket setQuantity(String itemId, int quantity) {
    if (quantity <= 0) return remove(itemId);
    return _with([
      for (final e in items)
        if (e.id == itemId) e.copyWith(quantity: _clamp(quantity)) else e,
    ]);
  }

  Basket setUnitPrice(String itemId, Money price) => _with([
    for (final e in items)
      if (e.id == itemId) e.copyWith(unitPrice: price) else e,
  ]);

  Basket remove(String itemId) => _with([
    for (final e in items)
      if (e.id != itemId) e,
  ]);

  Basket withPlace({String? id, String? name}) =>
      Basket(items: items, placeId: id, placeName: name);

  /// Empties the items, keeping the chosen place.
  Basket cleared() => Basket(placeId: placeId, placeName: placeName);

  Basket _with(List<BasketItem> next) =>
      Basket(items: next, placeId: placeId, placeName: placeName);

  static int _clamp(int q) => q.clamp(1, maxQuantity);

  static bool _sameLine(BasketItem a, BasketItem b) {
    if (a.unitPrice != b.unitPrice) return false;
    if (a.variantId != null || b.variantId != null) {
      return a.variantId == b.variantId;
    }
    if (a.productId != null || b.productId != null) {
      return a.productId == b.productId;
    }
    return a.name.trim().toLowerCase() == b.name.trim().toLowerCase();
  }
}
