import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/repositories/categories_repository.dart';
import '../../../../data/repositories/global_price_types_repository.dart';
import '../../../../data/repositories/payment_methods_repository.dart';
import '../../../../data/repositories/place_types_repository.dart';
import '../../../../data/services/database/seed_data.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/lookups.dart';

/// The four editable lists of Settings → Manage lists.
enum ManagedListKind {
  placeTypes('Place types', 'Add a place type', 'place_type'),
  categories('Categories', 'Add a category', 'category'),
  paymentMethods('Payment methods', 'Add a payment method', 'payment_method'),
  globalPriceTypes(
    'Global price types',
    'Add a price type',
    'global_price_type',
  );

  const ManagedListKind(this.title, this.addLabel, this.tableSlug);

  final String title;
  final String addLabel;

  /// `builtInId` table name of the starter rows.
  final String tableSlug;
}

/// One row in a managed list, whatever table it comes from.
class ManagedItem {
  const ManagedItem({
    required this.id,
    required this.name,
    required this.isBuiltIn,
    this.iconKey,
    this.detail,
    this.source,
  });

  final String id;
  final String name;
  final bool isBuiltIn;
  final String? iconKey;

  /// Small second line ("Shop", "Venue").
  final String? detail;

  /// The domain model this row came from (used to save a renamed copy).
  final Object? source;
}

/// Adds, renames, hides (soft-deletes), reorders and restores the rows of one list.
/// Built-in rows can be renamed or hidden but are never hard-deleted (DATA_MODEL § 1).
abstract class ManagedList {
  ManagedListKind get kind;

  Stream<List<ManagedItem>> watch();

  /// New row at the end. [placeKind] only matters for place types.
  Future<void> add(String name, {PlaceKind placeKind = PlaceKind.shop});

  Future<void> rename(ManagedItem item, String name);

  /// Soft delete. The row disappears from pickers; old data that uses it keeps working.
  Future<void> hide(ManagedItem item);

  /// Saves the new order (index = sort order).
  Future<void> reorder(List<ManagedItem> ordered);

  /// Brings back starter rows that were hidden. Returns how many.
  Future<int> restoreStarters(List<ManagedItem> current);

  /// How many starter rows exist for this list.
  int get starterCount;
}

final managedListProvider = Provider.family<ManagedList, ManagedListKind>((
  ref,
  kind,
) {
  return switch (kind) {
    ManagedListKind.placeTypes => _PlaceTypesList(
      ref.watch(placeTypesRepositoryProvider),
    ),
    ManagedListKind.categories => _CategoriesList(
      ref.watch(categoriesRepositoryProvider),
    ),
    ManagedListKind.paymentMethods => _PaymentMethodsList(
      ref.watch(paymentMethodsRepositoryProvider),
    ),
    ManagedListKind.globalPriceTypes => _GlobalTypesList(
      ref.watch(globalPriceTypesRepositoryProvider),
    ),
  };
});

final managedItemsProvider =
    StreamProvider.family<List<ManagedItem>, ManagedListKind>(
      (ref, kind) => ref.watch(managedListProvider(kind)).watch(),
    );

int _nextOrder(Iterable<int> orders) =>
    orders.isEmpty ? 0 : orders.reduce((a, b) => a > b ? a : b) + 1;

String _clean(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

class _PlaceTypesList implements ManagedList {
  _PlaceTypesList(this._repo);
  final PlaceTypesRepository _repo;

  @override
  ManagedListKind get kind => ManagedListKind.placeTypes;

  @override
  int get starterCount => seedPlaceTypes.length;

  @override
  Stream<List<ManagedItem>> watch() => _repo.watchAll().map(
    (rows) => [
      for (final r in rows)
        ManagedItem(
          id: r.id,
          name: r.name,
          isBuiltIn: r.isBuiltIn,
          iconKey: r.iconKey,
          detail: r.kind == PlaceKind.shop
              ? 'Shop · has products'
              : 'Venue · has a menu',
          source: r,
        ),
    ],
  );

  @override
  Future<void> add(String name, {PlaceKind placeKind = PlaceKind.shop}) async {
    final existing = await _repo.watchAll().first;
    await _repo.save(
      PlaceType(
        id: newId(),
        name: _clean(name),
        iconKey: placeKind == PlaceKind.shop ? 'storefront' : 'restaurant',
        kind: placeKind,
        sortOrder: _nextOrder(existing.map((e) => e.sortOrder)),
      ),
    );
  }

  @override
  Future<void> rename(ManagedItem item, String name) async {
    final r = item.source! as PlaceType;
    await _repo.save(
      PlaceType(
        id: r.id,
        name: _clean(name),
        iconKey: r.iconKey,
        kind: r.kind,
        sortOrder: r.sortOrder,
        isBuiltIn: r.isBuiltIn,
      ),
    );
  }

  @override
  Future<void> hide(ManagedItem item) => _repo.delete(item.id);

  @override
  Future<void> reorder(List<ManagedItem> ordered) async {
    for (final (i, item) in ordered.indexed) {
      final r = item.source! as PlaceType;
      if (r.sortOrder == i) continue;
      await _repo.save(
        PlaceType(
          id: r.id,
          name: r.name,
          iconKey: r.iconKey,
          kind: r.kind,
          sortOrder: i,
          isBuiltIn: r.isBuiltIn,
        ),
      );
    }
  }

  @override
  Future<int> restoreStarters(List<ManagedItem> current) async {
    final have = current.map((e) => e.id).toSet();
    var restored = 0;
    for (final (i, s) in seedPlaceTypes.indexed) {
      final id = builtInId(kind.tableSlug, s.slug);
      if (have.contains(id)) continue;
      await _repo.save(
        PlaceType(
          id: id,
          name: s.name,
          iconKey: s.iconKey,
          kind: s.kind,
          sortOrder: i,
          isBuiltIn: true,
        ),
      );
      restored++;
    }
    return restored;
  }
}

class _CategoriesList implements ManagedList {
  _CategoriesList(this._repo);
  final CategoriesRepository _repo;

  @override
  ManagedListKind get kind => ManagedListKind.categories;

  @override
  int get starterCount => seedCategories.length;

  @override
  Stream<List<ManagedItem>> watch() => _repo.watchAll().map(
    (rows) => [
      for (final r in rows)
        ManagedItem(
          id: r.id,
          name: r.name,
          isBuiltIn: r.isBuiltIn,
          iconKey: r.iconKey,
          source: r,
        ),
    ],
  );

  @override
  Future<void> add(String name, {PlaceKind placeKind = PlaceKind.shop}) async {
    final existing = await _repo.watchAll().first;
    await _repo.save(
      Category(
        id: newId(),
        name: _clean(name),
        iconKey: 'category',
        sortOrder: _nextOrder(existing.map((e) => e.sortOrder)),
      ),
    );
  }

  @override
  Future<void> rename(ManagedItem item, String name) async {
    final r = item.source! as Category;
    await _repo.save(
      Category(
        id: r.id,
        name: _clean(name),
        iconKey: r.iconKey,
        sortOrder: r.sortOrder,
        isBuiltIn: r.isBuiltIn,
      ),
    );
  }

  @override
  Future<void> hide(ManagedItem item) => _repo.delete(item.id);

  @override
  Future<void> reorder(List<ManagedItem> ordered) async {
    for (final (i, item) in ordered.indexed) {
      final r = item.source! as Category;
      if (r.sortOrder == i) continue;
      await _repo.save(
        Category(
          id: r.id,
          name: r.name,
          iconKey: r.iconKey,
          sortOrder: i,
          isBuiltIn: r.isBuiltIn,
        ),
      );
    }
  }

  @override
  Future<int> restoreStarters(List<ManagedItem> current) async {
    final have = current.map((e) => e.id).toSet();
    var restored = 0;
    for (final (i, s) in seedCategories.indexed) {
      final id = builtInId(kind.tableSlug, s.slug);
      if (have.contains(id)) continue;
      await _repo.save(
        Category(
          id: id,
          name: s.name,
          iconKey: s.iconKey,
          sortOrder: i,
          isBuiltIn: true,
        ),
      );
      restored++;
    }
    return restored;
  }
}

class _PaymentMethodsList implements ManagedList {
  _PaymentMethodsList(this._repo);
  final PaymentMethodsRepository _repo;

  @override
  ManagedListKind get kind => ManagedListKind.paymentMethods;

  @override
  int get starterCount => seedPaymentMethods.length;

  @override
  Stream<List<ManagedItem>> watch() => _repo.watchAll().map(
    (rows) => [
      for (final r in rows)
        ManagedItem(
          id: r.id,
          name: r.name,
          isBuiltIn: r.isBuiltIn,
          iconKey: r.iconKey,
          source: r,
        ),
    ],
  );

  @override
  Future<void> add(String name, {PlaceKind placeKind = PlaceKind.shop}) async {
    final existing = await _repo.watchAll().first;
    await _repo.save(
      PaymentMethod(
        id: newId(),
        name: _clean(name),
        iconKey: 'payment',
        sortOrder: _nextOrder(existing.map((e) => e.sortOrder)),
      ),
    );
  }

  @override
  Future<void> rename(ManagedItem item, String name) async {
    final r = item.source! as PaymentMethod;
    await _repo.save(
      PaymentMethod(
        id: r.id,
        name: _clean(name),
        iconKey: r.iconKey,
        sortOrder: r.sortOrder,
        isBuiltIn: r.isBuiltIn,
      ),
    );
  }

  @override
  Future<void> hide(ManagedItem item) => _repo.delete(item.id);

  @override
  Future<void> reorder(List<ManagedItem> ordered) async {
    for (final (i, item) in ordered.indexed) {
      final r = item.source! as PaymentMethod;
      if (r.sortOrder == i) continue;
      await _repo.save(
        PaymentMethod(
          id: r.id,
          name: r.name,
          iconKey: r.iconKey,
          sortOrder: i,
          isBuiltIn: r.isBuiltIn,
        ),
      );
    }
  }

  @override
  Future<int> restoreStarters(List<ManagedItem> current) async {
    final have = current.map((e) => e.id).toSet();
    var restored = 0;
    for (final (i, s) in seedPaymentMethods.indexed) {
      final id = builtInId(kind.tableSlug, s.slug);
      if (have.contains(id)) continue;
      await _repo.save(
        PaymentMethod(
          id: id,
          name: s.name,
          iconKey: s.iconKey,
          sortOrder: i,
          isBuiltIn: true,
        ),
      );
      restored++;
    }
    return restored;
  }
}

class _GlobalTypesList implements ManagedList {
  _GlobalTypesList(this._repo);
  final GlobalPriceTypesRepository _repo;

  @override
  ManagedListKind get kind => ManagedListKind.globalPriceTypes;

  @override
  int get starterCount => seedGlobalPriceTypes.length;

  @override
  Stream<List<ManagedItem>> watch() => _repo.watchAll().map(
    (rows) => [
      for (final r in rows)
        ManagedItem(id: r.id, name: r.name, isBuiltIn: r.isBuiltIn, source: r),
    ],
  );

  @override
  Future<void> add(String name, {PlaceKind placeKind = PlaceKind.shop}) async {
    final existing = await _repo.watchAll().first;
    await _repo.save(
      GlobalPriceType(
        id: newId(),
        name: _clean(name),
        sortOrder: _nextOrder(existing.map((e) => e.sortOrder)),
      ),
    );
  }

  @override
  Future<void> rename(ManagedItem item, String name) async {
    final r = item.source! as GlobalPriceType;
    await _repo.save(
      GlobalPriceType(
        id: r.id,
        name: _clean(name),
        sortOrder: r.sortOrder,
        isBuiltIn: r.isBuiltIn,
      ),
    );
  }

  @override
  Future<void> hide(ManagedItem item) => _repo.delete(item.id);

  @override
  Future<void> reorder(List<ManagedItem> ordered) async {
    for (final (i, item) in ordered.indexed) {
      final r = item.source! as GlobalPriceType;
      if (r.sortOrder == i) continue;
      await _repo.save(
        GlobalPriceType(
          id: r.id,
          name: r.name,
          sortOrder: i,
          isBuiltIn: r.isBuiltIn,
        ),
      );
    }
  }

  @override
  Future<int> restoreStarters(List<ManagedItem> current) async {
    final have = current.map((e) => e.id).toSet();
    var restored = 0;
    for (final (i, s) in seedGlobalPriceTypes.indexed) {
      final id = builtInId(kind.tableSlug, s.slug);
      if (have.contains(id)) continue;
      await _repo.save(
        GlobalPriceType(id: id, name: s.name, sortOrder: i, isBuiltIn: true),
      );
      restored++;
    }
    return restored;
  }
}
