import 'package:daftar/domain/models/basket.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

BasketItem item(
  String id,
  int millimes, {
  int qty = 1,
  String? name,
  String? productId,
  String? variantId,
}) => BasketItem(
  id: id,
  name: name ?? id,
  unitPrice: Money.tnd(millimes),
  quantity: qty,
  productId: productId,
  variantId: variantId,
);

void main() {
  test('empty basket totals zero', () {
    const b = Basket();
    expect(b.isEmpty, isTrue);
    expect(b.total, Money.zeroTnd);
    expect(b.itemCount, 0);
  });

  test('line total and running total are exact', () {
    final b = const Basket()
        .add(item('a', 1100, qty: 3))
        .add(item('b', 450, qty: 2));
    expect(b.items.first.lineTotal, const Money.tnd(3300));
    expect(b.total, const Money.tnd(4200));
    expect(b.itemCount, 5);
    expect(b.lineCount, 2);
  });

  test('same catalog variant and price merges quantities', () {
    final b = const Basket()
        .add(item('a', 1000, productId: 'p', variantId: 'v'))
        .add(item('b', 1000, qty: 2, productId: 'p', variantId: 'v'));
    expect(b.lineCount, 1);
    expect(b.items.single.quantity, 3);
  });

  test('different price or variant stays a separate line', () {
    final b = const Basket()
        .add(item('a', 1000, variantId: 'v1', productId: 'p'))
        .add(item('b', 1000, variantId: 'v2', productId: 'p'))
        .add(item('c', 900, variantId: 'v1', productId: 'p'));
    expect(b.lineCount, 3);
  });

  test('typed lines merge by name ignoring case and spaces', () {
    final b = const Basket()
        .add(item('a', 500, name: 'Milk'))
        .add(item('b', 500, name: ' milk '));
    expect(b.lineCount, 1);
    expect(b.itemCount, 2);
  });

  test('setQuantity clamps, and zero removes', () {
    var b = const Basket().add(item('a', 1000)).add(item('b', 500));
    b = b.setQuantity('a', 4);
    expect(b.items.first.quantity, 4);
    b = b.setQuantity('a', 500);
    expect(b.items.first.quantity, Basket.maxQuantity);
    b = b.setQuantity('a', 0);
    expect(b.lineCount, 1);
    expect(b.items.single.id, 'b');
  });

  test('setUnitPrice and remove', () {
    var b = const Basket().add(item('a', 1000, qty: 2));
    b = b.setUnitPrice('a', const Money.tnd(1250));
    expect(b.total, const Money.tnd(2500));
    b = b.remove('a');
    expect(b.isEmpty, isTrue);
  });

  test('place is kept when clearing and editing', () {
    var b = const Basket().withPlace(id: 'pl', name: 'Carrefour');
    b = b.add(item('a', 1000));
    expect(b.placeId, 'pl');
    b = b.cleared();
    expect(b.isEmpty, isTrue);
    expect(b.placeName, 'Carrefour');
    expect(b.withPlace().placeId, isNull);
  });

  test('immutability: add returns a new basket', () {
    const b = Basket();
    b.add(item('a', 1000));
    expect(b.isEmpty, isTrue);
  });
}
