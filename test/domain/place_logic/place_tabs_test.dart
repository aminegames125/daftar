import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/domain/place_logic/place_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

PlaceType type(String icon, PlaceKind kind) =>
    PlaceType(id: icon, name: icon, iconKey: icon, kind: kind);

void main() {
  test('shops get Products, History, Notes', () {
    final tabs = tabsFor(type('shopping_cart', PlaceKind.shop));
    expect(tabs.map((t) => t.label), ['Products', 'History', 'Notes']);
    expect(tabs.first.tab, PlaceTab.products);
  });

  test('food venues get Menu', () {
    for (final key in ['cafe', 'restaurant', 'fast_food']) {
      expect(tabsFor(type(key, PlaceKind.venue)).first.label, 'Menu');
    }
  });

  test('service venues get Price list', () {
    for (final key in [
      'content_cut',
      'car_wash',
      'fitness',
      'build',
      'custom',
    ]) {
      final tabs = tabsFor(type(key, PlaceKind.venue));
      expect(tabs.first.label, 'Price list');
      expect(tabs.first.tab, PlaceTab.menu);
    }
  });
}
