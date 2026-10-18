/// A place is either a shop (sells products) or a venue (has a menu / price list).
enum PlaceKind { shop, venue }

/// Editable lists the user manages in Settings. Built-in rows can be renamed or
/// hidden (soft-deleted) but are seeded once and never hard-deleted.
class PlaceType {
  const PlaceType({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.kind,
    this.sortOrder = 0,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String iconKey;
  final PlaceKind kind;
  final int sortOrder;
  final bool isBuiltIn;
}

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.iconKey,
    this.sortOrder = 0,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String iconKey;
  final int sortOrder;
  final bool isBuiltIn;
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.iconKey,
    this.sortOrder = 0,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String iconKey;
  final int sortOrder;
  final bool isBuiltIn;
}

/// Label for a price that is not tied to a store ("Reference price", …).
class GlobalPriceType {
  const GlobalPriceType({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final int sortOrder;
  final bool isBuiltIn;
}
