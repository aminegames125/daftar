import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/menu.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/models/price_entry.dart';

/// An option with its latest price at this place.
class MenuOptionView {
  const MenuOptionView({required this.option, this.latest});

  final MenuItemOption option;
  final PriceEntry? latest;
}

class MenuItemView {
  const MenuItemView({required this.item, required this.options});

  final MenuItem item;
  final List<MenuOptionView> options;

  /// Lowest latest price among the options (shown as "from ...").
  Money? get lowestPrice {
    final prices = [
      for (final o in options)
        if (o.latest != null) o.latest!.amount,
    ];
    return prices.isEmpty
        ? null
        : prices.reduce((a, b) => a.minor <= b.minor ? a : b);
  }

  bool get hasSizes =>
      options.length > 1 || options.any((o) => o.option.name != null);
}

/// A section of the menu. [section] is null for items that have none.
class MenuSectionView {
  const MenuSectionView({this.section, required this.items});

  final MenuSection? section;
  final List<MenuItemView> items;
}

class MenuData {
  const MenuData({required this.sections, required this.usual});

  final List<MenuSectionView> sections;

  /// ⭐ items ("Your usual"), shown first on the place page.
  final List<MenuItemView> usual;

  int get itemCount => sections.fold(0, (n, s) => n + s.items.length);
  bool get isEmpty => itemCount == 0;
}

/// Groups items under their sections (menu order), with unsectioned items first.
/// [latestByOption] maps option id → newest price at the place.
MenuData buildMenuData(
  List<MenuSection> sections,
  List<MenuItem> items,
  Map<String, PriceEntry> latestByOption,
) {
  MenuItemView view(MenuItem i) => MenuItemView(
    item: i,
    options: [
      for (final o in i.options)
        MenuOptionView(option: o, latest: latestByOption[o.id]),
    ],
  );

  final byId = {for (final s in sections) s.id: s};
  final unsectioned = [
    for (final i in items)
      if (i.sectionId == null || !byId.containsKey(i.sectionId)) view(i),
  ];
  return MenuData(
    sections: [
      if (unsectioned.isNotEmpty) MenuSectionView(items: unsectioned),
      for (final s in sections)
        MenuSectionView(
          section: s,
          items: [
            for (final i in items)
              if (i.sectionId == s.id) view(i),
          ],
        ),
    ],
    usual: [
      for (final i in items)
        if (i.isUsual) view(i),
    ],
  );
}

final menuSectionsProvider = StreamProvider.autoDispose
    .family<List<MenuSection>, String>(
      (ref, placeId) =>
          ref.watch(menuRepositoryProvider).watchSections(placeId),
    );

final menuItemsProvider = StreamProvider.autoDispose
    .family<List<MenuItem>, String>(
      (ref, placeId) => ref.watch(menuRepositoryProvider).watchItems(placeId),
    );

/// Newest price per option at this place. Refreshed by [MenuActions] after a write.
final menuLatestPricesProvider = FutureProvider.autoDispose
    .family<Map<String, PriceEntry>, String>((ref, placeId) async {
      final items = await ref.watch(menuItemsProvider(placeId).future);
      final prices = ref.read(pricesRepositoryProvider);
      final latest = <String, PriceEntry>{};
      for (final item in items) {
        for (final option in item.options) {
          final history = await prices
              .watchHistoryForMenuOption(option.id)
              .first;
          for (final e in history) {
            if (e.placeId == placeId) {
              latest[option.id] = e; // history is newest first
              break;
            }
          }
        }
      }
      return latest;
    });

/// The whole menu of a place, ready to draw.
final menuDataProvider = Provider.autoDispose
    .family<AsyncValue<MenuData>, String>((ref, placeId) {
      final sections = ref.watch(menuSectionsProvider(placeId));
      final items = ref.watch(menuItemsProvider(placeId));
      final prices = ref.watch(menuLatestPricesProvider(placeId));
      if (sections.hasError) {
        return AsyncError(sections.error!, sections.stackTrace!);
      }
      if (items.hasError) return AsyncError(items.error!, items.stackTrace!);
      final s = sections.value;
      final i = items.value;
      if (s == null || i == null) return const AsyncLoading();
      // Show the menu right away; prices fill in when they arrive.
      return AsyncData(buildMenuData(s, i, prices.value ?? const {}));
    });

/// An option being typed in the item editor.
class OptionInput {
  const OptionInput({this.id, this.name, this.price});

  final String? id;
  final String? name;

  /// null = no price yet.
  final Money? price;
}

/// Writes for the menu of one place. Option prices are normal price entries
/// (`PriceEntry.menuOptionId`) so history and best-option work.
class MenuActions {
  MenuActions(this._ref, this.placeId, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Ref _ref;
  final String placeId;
  final DateTime Function() _now;

  /// Adds a section at the end of the menu and returns its id.
  Future<String> addSection(String name) async {
    final existing = await _ref
        .read(menuRepositoryProvider)
        .watchSections(placeId)
        .first;
    final id = newId();
    await _ref
        .read(menuRepositoryProvider)
        .saveSection(
          MenuSection(
            id: id,
            placeId: placeId,
            name: name.trim(),
            sortOrder: existing.length,
          ),
        );
    return id;
  }

  Future<void> renameSection(MenuSection section, String name) => _ref
      .read(menuRepositoryProvider)
      .saveSection(
        MenuSection(
          id: section.id,
          placeId: placeId,
          name: name.trim(),
          sortOrder: section.sortOrder,
        ),
      );

  Future<void> deleteSection(String id) =>
      _ref.read(menuRepositoryProvider).deleteSection(id);

  /// Creates or updates an item. For a single price pass one option with a null
  /// name. Prices that differ from the option's latest price are logged as new
  /// entries; unchanged prices are not repeated.
  Future<String> saveItem({
    String? itemId,
    required String name,
    String? sectionId,
    bool isUsual = false,
    required List<OptionInput> options,
  }) async {
    final menu = _ref.read(menuRepositoryProvider);
    final id = itemId ?? newId();
    final existingItems = await menu.watchItems(placeId).first;
    final previous = existingItems.where((i) => i.id == id).firstOrNull;
    final single = options.length <= 1;

    final saved = <MenuItemOption>[];
    final priced = <(String, Money)>[];
    for (var n = 0; n < options.length; n++) {
      final input = options[n];
      final optionId = single
          ? builtInId('default_option', id)
          : (input.id ?? newId());
      saved.add(
        MenuItemOption(
          id: optionId,
          menuItemId: id,
          name: single || (input.name ?? '').trim().isEmpty
              ? null
              : input.name!.trim(),
          sortOrder: n,
        ),
      );
      final price = input.price;
      if (price != null && price.minor > 0) priced.add((optionId, price));
    }

    await menu.saveItem(
      MenuItem(
        id: id,
        placeId: placeId,
        sectionId: sectionId,
        name: name.trim(),
        isUsual: isUsual,
        sortOrder: previous?.sortOrder ?? existingItems.length,
        options: saved,
      ),
    );
    for (final (optionId, price) in priced) {
      await logPrice(optionId, price);
    }
    _ref.invalidate(menuLatestPricesProvider(placeId));
    return id;
  }

  /// Logs [price] for an option unless it equals the newest one already stored.
  Future<void> logPrice(String menuOptionId, Money price) async {
    final prices = _ref.read(pricesRepositoryProvider);
    final history = await prices.watchHistoryForMenuOption(menuOptionId).first;
    final latest = history.where((e) => e.placeId == placeId).firstOrNull;
    if (latest != null &&
        latest.amount == price &&
        latest.amountMax == null &&
        !latest.isPromo) {
      return;
    }
    await prices.save(
      PriceEntry(
        id: newId(),
        menuOptionId: menuOptionId,
        placeId: placeId,
        amount: price,
        seenAt: _now(),
      ),
    );
    _ref.invalidate(menuLatestPricesProvider(placeId));
  }

  Future<void> setUsual(String itemId, {required bool isUsual}) =>
      _ref.read(menuRepositoryProvider).setUsual(itemId, isUsual: isUsual);

  Future<void> deleteItem(String itemId) async {
    await _ref.read(menuRepositoryProvider).deleteItem(itemId);
    _ref.invalidate(menuLatestPricesProvider(placeId));
  }
}

final menuActionsProvider = Provider.family<MenuActions, String>(
  (ref, placeId) => MenuActions(ref, placeId),
);
