import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/saved_list.dart';
import 'package:daftar/ui/features/calculator/view_models/saved_lists_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 17);

PriceEntry _offer(String variant, String place, int millimes, {int ago = 0}) =>
    PriceEntry(
      id: '$variant-$place',
      variantId: variant,
      placeId: place,
      amount: Money.tnd(millimes),
      seenAt: _now.subtract(Duration(days: ago)),
    );

SavedListItem _item(
  String id, {
  String? variant,
  String? text,
  int qty = 1,
  bool checked = false,
}) => SavedListItem(
  id: id,
  listId: 'l',
  variantId: variant,
  freeText: text,
  quantity: qty,
  isChecked: checked,
);

void main() {
  test('picks the cheapest complete store and totals quantity x price', () {
    final s = summarizeSavedList(
      items: [
        _item('1', variant: 'milk', qty: 2),
        _item('2', variant: 'oil'),
      ],
      offersByVariant: {
        'milk': [_offer('milk', 'a', 1000), _offer('milk', 'b', 900)],
        'oil': [_offer('oil', 'a', 5000), _offer('oil', 'b', 5000)],
      },
      now: _now,
    );
    expect(s.bestPlaceId, 'b');
    expect(s.total, const Money.tnd(6800));
    expect(s.unpricedCount, 0);
    expect(s.unitPrices['milk'], const Money.tnd(900));
  });

  test('typed items and unknown prices count as unpriced', () {
    final s = summarizeSavedList(
      items: [
        _item('1', variant: 'milk'),
        _item('2', text: 'Bread'),
        _item('3', variant: 'ghost'),
      ],
      offersByVariant: {
        'milk': [_offer('milk', 'a', 1000)],
        'ghost': const [],
      },
      now: _now,
    );
    expect(s.total, const Money.tnd(1000));
    expect(s.unpricedCount, 2);
  });

  test('no price at all gives no total', () {
    final s = summarizeSavedList(
      items: [
        _item('1', text: 'Bread', checked: true),
        _item('2', text: 'Tea'),
      ],
      offersByVariant: const {},
      now: _now,
    );
    expect(s.total, isNull);
    expect(s.bestPlaceId, isNull);
    expect(s.unpricedCount, 2);
    expect(s.checkedCount, 1);
    expect(s.progress, 0.5);
  });

  test('global prices are ignored and an empty list is safe', () {
    final global = PriceEntry(
      id: 'g',
      variantId: 'milk',
      globalTypeId: 't',
      amount: const Money.tnd(800),
      seenAt: _now,
    );
    final s = summarizeSavedList(
      items: [_item('1', variant: 'milk')],
      offersByVariant: {
        'milk': [global],
      },
      now: _now,
    );
    expect(s.total, isNull);
    final empty = summarizeSavedList(
      items: const [],
      offersByVariant: const {},
      now: _now,
    );
    expect(empty.progress, 0);
    expect(empty.isDone, isFalse);
  });
}
