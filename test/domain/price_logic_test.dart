import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/domain/use_cases/price_change.dart';
import 'package:daftar/domain/use_cases/search_matcher.dart';
import 'package:daftar/domain/use_cases/variant_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 16);

PriceEntry entry(
  String id,
  int millimes,
  DateTime seen, {
  String place = 'a',
}) => PriceEntry(
  id: id,
  variantId: 'v',
  placeId: place,
  amount: Money.tnd(millimes),
  seenAt: seen,
);

void main() {
  group('priceChange', () {
    test('up is positive and says since when', () {
      final change = priceChange(
        entry('n', 5600, DateTime(2026, 10, 1)),
        entry('o', 5000, DateTime(2026, 3, 10)),
      )!;
      expect(change.percent, 12);
      expect(change.isUp, isTrue);
      expect(change.label(now), '+12% since March');
    });

    test('down is negative and adds the year when it is not this year', () {
      final change = priceChange(
        entry('n', 4000, DateTime(2026, 10, 1)),
        entry('o', 5000, DateTime(2025, 3, 10)),
      )!;
      expect(change.percent, -20);
      expect(change.isDown, isTrue);
      expect(change.label(now), '-20% since March 2025');
    });

    test('no change gives null and tiny changes show at least 1%', () {
      expect(priceChange(entry('n', 5000, now), entry('o', 5000, now)), isNull);
      expect(
        priceChange(entry('n', 10001, now), entry('o', 10000, now))!.percent,
        1,
      );
      expect(
        priceChange(entry('n', 9999, now), entry('o', 10000, now))!.percent,
        -1,
      );
    });

    test('changesByEntry compares each entry with the previous one of the same store', () {
      final history = [
        entry('a2', 5500, DateTime(2026, 10, 1)),
        entry('a1', 5000, DateTime(2026, 6, 1)),
        entry('b1', 4000, DateTime(2026, 9, 1), place: 'b'),
      ];
      final changes = changesByEntry(history);
      expect(changes.keys, ['a2']);
      expect(changes['a2']!.percent, 10);
    });
  });

  group('SearchQuery', () {
    test('ranks exact > prefix > token prefix > contains', () {
      final q = SearchQuery('Milka');
      expect(q.match('milka'), MatchRank.exact);
      expect(q.match('milka oreo'), MatchRank.prefix);
      expect(q.match('chocolat milka'), MatchRank.tokenPrefix);
      expect(q.match('lamilkar'), MatchRank.contains);
      expect(q.match('oreo'), isNull);
    });

    test('every token must match some token start', () {
      final q = SearchQuery('mil oreo');
      expect(q.match('milka oreo 100 g'), MatchRank.tokenPrefix);
      expect(q.match('milka noisette'), isNull);
    });

    test('is accent-insensitive on both sides', () {
      expect(SearchQuery('Café').match('cafe'), MatchRank.exact);
      expect(SearchQuery('crepes').match('crepes nutella'), MatchRank.prefix);
    });

    test('an empty query matches nothing', () {
      expect(SearchQuery('  ').match('milka'), isNull);
      expect(SearchQuery('  ').isEmpty, isTrue);
    });

    test('matchAny returns the best rank', () {
      expect(
        SearchQuery('oreo').matchAny(['chocolat milka oreo', 'oreo']),
        MatchRank.exact,
      );
    });
  });

  group('resolveVariant', () {
    var n = 0;
    String nextId() => 'new${n++}';
    const milka = Product(
      id: 'p',
      name: 'Milka',
      variants: [
        Variant(
          id: 'oreo',
          productId: 'p',
          name: 'Oreo',
          sizeValue: 100,
          sizeUnit: SizeUnit.g,
        ),
        Variant(id: 'plain', productId: 'p', name: 'Lait'),
      ],
    );

    setUp(() => n = 0);

    test('reuses a variant with the same name and size', () {
      final r = resolveVariant(
        product: milka,
        newVariantId: nextId,
        variantName: 'oreo',
        sizeValue: 0.1,
        sizeUnit: SizeUnit.kg,
      );
      expect(r.variant.id, 'oreo');
      expect(r.changed, isFalse);
    });

    test('reuses a sized variant when no size is typed', () {
      final r = resolveVariant(
        product: milka,
        newVariantId: nextId,
        variantName: 'Oreo',
      );
      expect(r.variant.id, 'oreo');
      expect(r.changed, isFalse);
    });

    test('a different size becomes a new variant', () {
      final r = resolveVariant(
        product: milka,
        newVariantId: nextId,
        variantName: 'Oreo',
        sizeValue: 300,
        sizeUnit: SizeUnit.g,
      );
      expect(r.variant.id, 'new0');
      expect(r.variant.baseQuantity, 300);
      expect(r.product.variants, hasLength(3));
      expect(r.changed, isTrue);
    });

    test('fills in a missing size on the same-name variant', () {
      final r = resolveVariant(
        product: milka,
        newVariantId: nextId,
        variantName: 'Lait',
        sizeValue: 250,
        sizeUnit: SizeUnit.g,
      );
      expect(r.variant.id, 'plain');
      expect(r.variant.baseQuantity, 250);
      expect(r.product.variants, hasLength(2));
      expect(r.changed, isTrue);
    });

    test('a new name adds a variant', () {
      final r = resolveVariant(
        product: milka,
        newVariantId: nextId,
        variantName: 'Noisette',
      );
      expect(r.variant.name, 'Noisette');
      expect(r.product.variants.map((v) => v.id), ['oreo', 'plain', 'new0']);
    });

    test('a brand-new product gets one default variant with the barcode', () {
      const fresh = Product(id: 'q', name: 'Water');
      final r = resolveVariant(
        product: fresh,
        newVariantId: nextId,
        sizeValue: 1.5,
        sizeUnit: SizeUnit.l,
        barcode: ' 6191 ',
      );
      expect(r.variant.name, isNull);
      expect(r.variant.barcode, '6191');
      expect(r.variant.baseQuantity, 1500);
      expect(r.product.variants, hasLength(1));
    });

    test('attaches a scanned barcode to a variant that has none', () {
      final r = resolveVariant(
        product: milka,
        newVariantId: nextId,
        variantName: 'Oreo',
        barcode: '123',
      );
      expect(r.variant.barcode, '123');
      expect(r.changed, isTrue);
    });
  });
}
