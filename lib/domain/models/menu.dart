class MenuSection {
  const MenuSection({
    required this.id,
    required this.placeId,
    required this.name,
    this.sortOrder = 0,
  });

  final String id;
  final String placeId;
  final String name;
  final int sortOrder;
}

/// A size/option of a menu item with its own price ("S", "L", "+cheese").
/// `name == null` means the item has a single price.
class MenuItemOption {
  const MenuItemOption({
    required this.id,
    required this.menuItemId,
    this.name,
    this.sortOrder = 0,
  });

  final String id;
  final String menuItemId;
  final String? name;
  final int sortOrder;
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.placeId,
    required this.name,
    this.sectionId,
    this.isUsual = false,
    this.sortOrder = 0,
    this.options = const [],
  });

  final String id;
  final String placeId;
  final String? sectionId;
  final String name;

  /// ⭐ "Your usual": shown at the top of the place page.
  final bool isUsual;
  final int sortOrder;
  final List<MenuItemOption> options;
}
