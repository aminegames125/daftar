import '../models/lookups.dart';

enum PlaceTab { products, menu, history, notes }

/// A tab of the place page.
typedef PlaceTabInfo = ({PlaceTab tab, String label});

/// Icon keys of place types that have a food/drink *menu*; other venues
/// (hairdresser, car wash, gym, service) have a *price list*.
// DECISION(owner): "Menu" vs "Price list" is decided by the type's icon key.
const _menuIconKeys = {'cafe', 'restaurant', 'fast_food'};

/// Tabs for a place of [type] (D25): shops get Products, venues get Menu or
/// Price list, and every place gets History and Notes.
List<PlaceTabInfo> tabsFor(PlaceType type) => [
  switch (type.kind) {
    PlaceKind.shop => (tab: PlaceTab.products, label: 'Products'),
    PlaceKind.venue => (
      tab: PlaceTab.menu,
      label: _menuIconKeys.contains(type.iconKey) ? 'Menu' : 'Price list',
    ),
  },
  (tab: PlaceTab.history, label: 'History'),
  (tab: PlaceTab.notes, label: 'Notes'),
];
