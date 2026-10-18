import 'dart:async';

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/prices_repository.dart';
import 'package:daftar/data/repositories/saved_lists_repository.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/domain/models/saved_list.dart';
import 'package:daftar/ui/features/calculator/view_models/calculator_providers.dart';
import 'package:daftar/ui/features/calculator/view_models/saved_lists_providers.dart';
import 'package:daftar/ui/features/calculator/views/saved_list_detail_screen.dart';
import 'package:daftar/ui/features/calculator/views/saved_lists_screen.dart';
import 'package:daftar/ui/features/products/view_models/catalog_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../core/test_app.dart';

/// In-memory repository whose streams replay the current value to listeners.
class FakeSavedLists implements SavedListsRepository {
  final lists = <SavedList>[];
  final items = <SavedListItem>[];
  final _tick = StreamController<void>.broadcast();

  Stream<T> _live<T>(T Function() read) async* {
    yield read();
    await for (final _ in _tick.stream) {
      yield read();
    }
  }

  void _changed() => _tick.add(null);

  List<SavedListItem> _of(String listId) =>
      items.where((i) => i.listId == listId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Stream<List<SavedList>> watchAll() => _live(() => List.of(lists));

  @override
  Stream<List<SavedListItem>> watchItems(String listId) =>
      _live(() => _of(listId));

  @override
  Future<SavedList?> getById(String id) async =>
      lists.where((l) => l.id == id).firstOrNull;

  @override
  Future<List<SavedList>> search(String query) async => lists;

  @override
  Future<void> save(SavedList list) async {
    lists
      ..removeWhere((l) => l.id == list.id)
      ..add(list);
    _changed();
  }

  @override
  Future<void> delete(String id) async {
    lists.removeWhere((l) => l.id == id);
    items.removeWhere((i) => i.listId == id);
    _changed();
  }

  @override
  Future<void> saveItem(SavedListItem item) async {
    items
      ..removeWhere((i) => i.id == item.id)
      ..add(item);
    _changed();
  }

  void _patch(String id, SavedListItem Function(SavedListItem) f) {
    final i = items.indexWhere((e) => e.id == id);
    if (i >= 0) items[i] = f(items[i]);
    _changed();
  }

  @override
  Future<void> setChecked(String itemId, bool checked) async =>
      _patch(itemId, (i) => i.copyWith(isChecked: checked));

  @override
  Future<void> setQuantity(String itemId, int quantity) async =>
      _patch(itemId, (i) => i.copyWith(quantity: quantity));

  @override
  Future<void> deleteItem(String itemId) async {
    items.removeWhere((i) => i.id == itemId);
    _changed();
  }

  @override
  Future<void> uncheckAll(String listId) async {
    for (var n = 0; n < items.length; n++) {
      if (items[n].listId == listId) {
        items[n] = items[n].copyWith(isChecked: false);
      }
    }
    _changed();
  }

  @override
  Future<void> reorderItems(String listId, List<String> itemIds) async {
    for (final (n, id) in itemIds.indexed) {
      _patch(id, (i) => i.copyWith(sortOrder: n));
    }
  }
}

class FakePrices implements PricesRepository {
  FakePrices(this.offers);
  final Map<String, List<PriceEntry>> offers;

  @override
  Future<List<PriceEntry>> currentOffersForVariant(String variantId) async =>
      offers[variantId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _milk = Product(
  id: 'p-milk',
  name: 'Milk',
  variants: [Variant(id: 'v-milk', productId: 'p-milk')],
);
const _oil = Product(
  id: 'p-oil',
  name: 'Olive oil',
  variants: [Variant(id: 'v-oil', productId: 'p-oil')],
);

PriceEntry _offer(String variant, String place, int millimes) => PriceEntry(
  id: '$variant-$place',
  variantId: variant,
  placeId: place,
  amount: Money.tnd(millimes),
  seenAt: DateTime(2026, 10, 17),
);

Future<(FakeSavedLists, List<Override>)> _setup() async {
  final repo = FakeSavedLists();
  await repo.save(const SavedList(id: 'l1', name: 'Monthly groceries'));
  await repo.saveItem(
    const SavedListItem(
      id: 'i1',
      listId: 'l1',
      variantId: 'v-milk',
      quantity: 2,
      sortOrder: 0,
    ),
  );
  await repo.saveItem(
    const SavedListItem(
      id: 'i2',
      listId: 'l1',
      freeText: 'Fresh bread',
      sortOrder: 1,
    ),
  );
  await repo.saveItem(
    const SavedListItem(
      id: 'i3',
      listId: 'l1',
      variantId: 'v-oil',
      sortOrder: 2,
    ),
  );
  return (
    repo,
    [
      savedListsRepositoryProvider.overrideWithValue(repo),
      pricesRepositoryProvider.overrideWithValue(
        FakePrices({
          'v-milk': [_offer('v-milk', 'a', 1200), _offer('v-milk', 'b', 1000)],
          'v-oil': [_offer('v-oil', 'a', 9000), _offer('v-oil', 'b', 9500)],
        }),
      ),
      productsProvider.overrideWith((ref) => Stream.value(const [_milk, _oil])),
      allPlacesProvider.overrideWith(
        (ref) => Stream.value(const [
          Place(id: 'a', name: 'Carrefour', typeId: 't'),
          Place(id: 'b', name: 'Monoprix', typeId: 't'),
        ]),
      ),
    ],
  );
}

Future<void> _size(WidgetTester tester, double w, [double h = 800]) async {
  tester.view.physicalSize = Size(w, h) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

void main() {
  group('actions', () {
    test(
      'saveBasket stores catalog and typed lines; useAsBasket loads them',
      () async {
        final (repo, overrides) = await _setup();
        final container = ProviderContainer(overrides: overrides);
        addTearDown(container.dispose);
        container
          ..listen(productsProvider, (_, _) {})
          ..listen(allPlacesProvider, (_, _) {})
          ..listen(savedListsProvider, (_, _) {})
          ..listen(savedListSummaryProvider('l1'), (_, _) {});
        await container.read(productsProvider.future);
        await container.read(allPlacesProvider.future);

        final basketVm = container.read(basketProvider.notifier);
        basketVm.add(
          name: 'Milk',
          unitPrice: const Money.tnd(1000),
          quantity: 3,
          productId: 'p-milk',
          variantId: 'v-milk',
        );
        basketVm.add(name: 'Dates', unitPrice: const Money.tnd(4000));

        final actions = container.read(savedListsActionsProvider);
        final id = await actions.saveBasket(
          'From basket',
          container.read(basketProvider),
        );
        final saved = repo.items.where((i) => i.listId == id).toList();
        expect(saved.length, 2);
        expect(saved[0].variantId, 'v-milk');
        expect(saved[0].quantity, 3);
        expect(saved[1].freeText, 'Dates');

        final mode = await actions.useAsBasket('l1');
        expect(mode, CalculatorMode.bestStore);
        expect(
          container.read(calculatorModeProvider),
          CalculatorMode.bestStore,
        );
        final basket = container.read(basketProvider);
        expect(basket.placeId, 'a');
        expect(basket.placeName, 'Carrefour');
        expect(basket.lineCount, 3);
        final milk = basket.items.firstWhere((i) => i.variantId == 'v-milk');
        expect(milk.unitPrice, const Money.tnd(1200));
        expect(milk.productId, 'p-milk');
        expect(
          basket.items.firstWhere((i) => i.name == 'Fresh bread').unitPrice,
          Money.zeroTnd,
        );
      },
    );

    test('adding a variant already on the list raises its quantity', () async {
      final (repo, overrides) = await _setup();
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      await container
          .read(savedListsActionsProvider)
          .addItem('l1', variantId: 'v-milk', quantity: 1);
      expect(
        repo.items.where((i) => i.variantId == 'v-milk').single.quantity,
        3,
      );
      await container.read(savedListsActionsProvider).createList(' Party ');
      expect(repo.lists.last.name, 'Party');
    });
  });

  group('screens', () {
    testWidgets('lists screen shows progress, best store and total', (
      tester,
    ) async {
      final (repo, overrides) = await _setup();
      await repo.setChecked('i1', true);
      await tester.pumpWidget(
        testApp(
          const SavedListsScreen(),
          overrides: overrides,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Monthly groceries'), findsOneWidget);
      expect(find.text('1 of 3 done'), findsOneWidget);
      expect(find.text('Best store · Carrefour'), findsOneWidget);
      // 2 x 1.200 + 9.000 at Carrefour; the typed item has no price.
      expect(find.text('11.400'), findsOneWidget);
      expect(find.text('1 item has no price'), findsOneWidget);
    });

    testWidgets('checking items updates progress; uncheck all resets', (
      tester,
    ) async {
      final (repo, overrides) = await _setup();
      await tester.pumpWidget(
        testApp(
          const SavedListDetailScreen(listId: 'l1'),
          overrides: overrides,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 of 3 done'), findsOneWidget);

      await tester.tap(find.byType(InkResponse).at(1));
      await tester.pumpAndSettle();
      expect(repo.items.firstWhere((i) => i.id == 'i2').isChecked, isTrue);
      expect(find.text('1 of 3 done'), findsOneWidget);

      await tester.tap(find.byTooltip('Uncheck all'));
      await tester.pumpAndSettle();
      expect(find.text('0 of 3 done'), findsOneWidget);
    });

    testWidgets('swipe removes an item', (tester) async {
      final (repo, overrides) = await _setup();
      await tester.pumpWidget(
        testApp(
          const SavedListDetailScreen(listId: 'l1'),
          overrides: overrides,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.text('Fresh bread'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Fresh bread'), findsNothing);
      expect(repo.items.any((i) => i.id == 'i2'), isFalse);
    });

    testWidgets('use as basket jumps to Best store mode', (tester) async {
      final (_, overrides) = await _setup();
      await tester.pumpWidget(
        testApp(
          const SavedListDetailScreen(listId: 'l1'),
          overrides: overrides,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      final container = _container(tester, SavedListDetailScreen);
      final mode = await container
          .read(savedListsActionsProvider)
          .useAsBasket('l1');
      expect(mode, CalculatorMode.bestStore);
      expect(container.read(basketProvider).lineCount, 3);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('no overflow at 320 dp, text x$scale', (tester) async {
        await _size(tester, 320, 640);
        final (repo, overrides) = await _setup();
        await repo.setChecked('i1', true);
        await repo.save(
          const SavedList(
            id: 'l2',
            name: 'A very long list name that keeps going and going',
            sortOrder: 1,
          ),
        );
        for (final screen in <Widget>[
          const SavedListsScreen(),
          const SavedListDetailScreen(listId: 'l1'),
        ]) {
          await tester.pumpWidget(
            testApp(
              screen,
              overrides: overrides,
              textScale: scale,
              reduceMotion: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
