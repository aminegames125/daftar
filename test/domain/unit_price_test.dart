import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/domain/use_cases/unit_price.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unitPriceFor', () {
    test('100 g at 4.400 is 44.000 per kg', () {
      final u = unitPriceFor(const Money.tnd(4400), 100, SizeUnit.g)!;
      expect(u.price, const Money.tnd(44000));
      expect(u.label, '= 44.000 TND / kg');
    });

    test('volumes are per litre and pieces per piece', () {
      expect(
        unitPriceFor(const Money.tnd(900), 500, SizeUnit.ml)!.label,
        '= 1.800 TND / L',
      );
      expect(
        unitPriceFor(const Money.tnd(6000), 6, SizeUnit.pc)!.label,
        '= 1.000 TND / pc',
      );
    });

    test('rounds to the nearest millime', () {
      expect(
        unitPriceFor(const Money.tnd(1000), 300, SizeUnit.g)!.price,
        const Money.tnd(3333),
      );
    });

    test(
      'is hidden without a size, or when the size already is the reference',
      () {
        expect(unitPriceFor(const Money.tnd(4400), null, SizeUnit.g), isNull);
        expect(unitPriceFor(const Money.tnd(4400), 0, SizeUnit.g), isNull);
        expect(unitPriceFor(const Money.tnd(4400), 1, SizeUnit.kg), isNull);
        expect(unitPriceFor(const Money.tnd(4400), 1, SizeUnit.pc), isNull);
      },
    );
  });

  test('formatSize and parseSize', () {
    expect(formatSize(100, SizeUnit.g), '100 g');
    expect(formatSize(1.5, SizeUnit.l), '1.5 L');
    expect(parseSize('1,5'), 1.5);
    expect(parseSize(' 100 '), 100);
    expect(parseSize(''), isNull);
    expect(parseSize('0'), isNull);
    expect(parseSize('abc'), isNull);
  });

  group('suggestProducts', () {
    const products = [
      Product(
        id: '1',
        name: 'Milka',
        brand: 'Mondelez',
        variants: [Variant(id: 'a', productId: '1', name: 'Oreo')],
      ),
      Product(id: '2', name: 'Chocolat Milka noir'),
      Product(id: '3', name: 'Lait'),
      Product(id: '4', name: 'Café Moka'),
    ];

    test('ranks by match quality', () {
      expect(suggestProducts(products, 'milka').map((p) => p.id), ['1', '2']);
    });

    test('finds through a variant name and is accent-insensitive', () {
      expect(suggestProducts(products, 'milka oreo').map((p) => p.id), ['1']);
      expect(suggestProducts(products, 'cafe').map((p) => p.id), ['4']);
    });

    test('empty query and limit', () {
      expect(suggestProducts(products, ''), isEmpty);
      expect(suggestProducts(products, 'm', limit: 2), hasLength(2));
    });
  });
}
