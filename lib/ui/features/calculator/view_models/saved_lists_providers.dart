import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/basket.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/models/saved_list.dart';
import '../../products/view_models/catalog_providers.dart';
import 'calculator_providers.dart';
import 'saved_lists_pricing.dart';

/// Every live list, in order.
final savedListsProvider = StreamProvider<List<SavedList>>(
  (ref) => ref.watch(savedListsRepositoryProvider).watchAll(),
);

/// One list by id (null while loading or once deleted).
final savedListByIdProvider = Provider.family<SavedList?, String>((ref, id) {
  final lists = ref.watch(savedListsProvider).value;
  if (lists == null) return null;
  for (final l in lists) {
    if (l.id == id) return l;
  }
  return null;
});

final savedListItemsProvider =
    StreamProvider.family<List<SavedListItem>, String>(
      (ref, listId) =>
          ref.watch(savedListsRepositoryProvider).watchItems(listId),
    );

/// Variant id -> "Milka · Oreo", for showing catalog lines.
final variantLabelsProvider = Provider<Map<String, String>>((ref) {
  final products = ref.watch(productsProvider).value ?? const [];
  return {
    for (final p in products)
      for (final v in p.variants)
        v.id: (v.name?.trim().isNotEmpty ?? false)
            ? '${p.name} · ${v.name!.trim()}'
            : p.name,
  };
});

/// The list's progress plus its best store and total, priced with the latest
/// offers. Recomputed whenever the items change.
final savedListSummaryProvider =
    FutureProvider.family<SavedListSummary, String>((ref, listId) async {
      final items = await ref.watch(savedListItemsProvider(listId).future);
      final prices = ref.read(pricesRepositoryProvider);
      final offers = <String, List<PriceEntry>>{};
      for (final id in {
        for (final i in items)
          if (i.variantId != null) i.variantId!,
      }) {
        offers[id] = await prices.currentOffersForVariant(id);
      }
      return summarizeSavedList(
        items: items,
        offersByVariant: offers,
        now: ref.read(clockProvider)(),
      );
    });

/// The list changes the screens ask for. Plain class over the repository so
/// the views stay free of data access.
class SavedListsActions {
  SavedListsActions(this._ref);

  final Ref _ref;

  static const maxQuantity = Basket.maxQuantity;

  Future<String> createList(String name) async {
    final lists = _ref.read(savedListsProvider).value ?? const <SavedList>[];
    final id = newId();
    await _ref
        .read(savedListsRepositoryProvider)
        .save(
          SavedList(
            id: id,
            name: name.trim(),
            sortOrder: lists.isEmpty ? 0 : lists.last.sortOrder + 1,
          ),
        );
    return id;
  }

  Future<void> rename(SavedList list, String name) => _ref
      .read(savedListsRepositoryProvider)
      .save(
        SavedList(id: list.id, name: name.trim(), sortOrder: list.sortOrder),
      );

  Future<void> deleteList(String id) =>
      _ref.read(savedListsRepositoryProvider).delete(id);

  /// Adds a catalog line (when [variantId] is set) or a typed one. Adding a
  /// variant that is already on the list raises its quantity instead.
  Future<void> addItem(
    String listId, {
    String? variantId,
    String? freeText,
    int quantity = 1,
  }) async {
    final repo = _ref.read(savedListsRepositoryProvider);
    final items = await repo.watchItems(listId).first;
    final text = freeText?.trim();
    if (variantId != null) {
      for (final i in items) {
        if (i.variantId == variantId) {
          return repo.setQuantity(
            i.id,
            (i.quantity + quantity).clamp(1, maxQuantity),
          );
        }
      }
    }
    await repo.saveItem(
      SavedListItem(
        id: newId(),
        listId: listId,
        variantId: variantId,
        freeText: variantId != null ? null : text,
        quantity: quantity,
        sortOrder: items.isEmpty ? 0 : items.last.sortOrder + 1,
      ),
    );
  }

  Future<void> setChecked(String itemId, bool checked) =>
      _ref.read(savedListsRepositoryProvider).setChecked(itemId, checked);

  Future<void> setQuantity(SavedListItem item, int quantity) {
    final repo = _ref.read(savedListsRepositoryProvider);
    return quantity <= 0
        ? repo.deleteItem(item.id)
        : repo.setQuantity(item.id, quantity.clamp(1, maxQuantity));
  }

  Future<void> removeItem(String itemId) =>
      _ref.read(savedListsRepositoryProvider).deleteItem(itemId);

  Future<void> uncheckAll(String listId) =>
      _ref.read(savedListsRepositoryProvider).uncheckAll(listId);

  Future<void> reorder(String listId, List<String> itemIds) =>
      _ref.read(savedListsRepositoryProvider).reorderItems(listId, itemIds);

  /// "Save basket as list": a new list holding the basket's lines.
  Future<String> saveBasket(String name, Basket basket) async {
    final id = await createList(name);
    for (final item in basket.items) {
      await addItem(
        id,
        variantId: item.variantId,
        freeText: item.variantId == null ? item.name : null,
        quantity: item.quantity,
      );
    }
    return id;
  }

  /// "Use as basket": replaces the basket with the list, priced at the best
  /// store (lines with no price come in at 0.000 to be filled in). Returns the
  /// mode to show: Best store when the list has prices, else Basket.
  Future<CalculatorMode> useAsBasket(String listId) async {
    final summary = await _ref.read(savedListSummaryProvider(listId).future);
    final labels = _ref.read(variantLabelsProvider);
    final places = _ref.read(placesByIdProvider);
    final productOf = {
      for (final p in _ref.read(productsProvider).value ?? const <Product>[])
        for (final v in p.variants) v.id: p.id,
    };
    final vm = _ref.read(basketProvider.notifier)..clear();
    for (final i in summary.items) {
      final v = i.variantId;
      vm.add(
        name: (v == null ? i.freeText : labels[v]) ?? 'Item',
        unitPrice: (v == null ? null : summary.unitPrices[v]) ?? Money.zeroTnd,
        quantity: i.quantity,
        variantId: v,
        productId: productOf[v],
      );
    }
    final placeId = summary.bestPlaceId;
    vm.setPlace(
      id: placeId,
      name: placeId == null ? null : places[placeId]?.name,
    );
    final mode = summary.hasPrice
        ? CalculatorMode.bestStore
        : CalculatorMode.basket;
    _ref.read(calculatorModeProvider.notifier).select(mode);
    return mode;
  }
}

final savedListsActionsProvider = Provider<SavedListsActions>(
  SavedListsActions.new,
);
