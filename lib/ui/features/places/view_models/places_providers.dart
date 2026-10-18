import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/photo.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/search/normalize_for_search.dart';

/// Every (non-deleted) place, A to Z.
final placesProvider = StreamProvider<List<Place>>(
  (ref) => ref.watch(placesRepositoryProvider).watchAll(),
);

final placeProvider = StreamProvider.autoDispose.family<Place?, String>(
  (ref, id) => ref.watch(placesRepositoryProvider).watch(id),
);

final placeTypesProvider = StreamProvider<List<PlaceType>>(
  (ref) => ref.watch(placeTypesRepositoryProvider).watchAll(),
);

final paymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodsRepositoryProvider).watchAll(),
);

final placePhotosProvider = StreamProvider.autoDispose
    .family<List<Photo>, String>(
      (ref, placeId) => ref
          .watch(photosRepositoryProvider)
          .watchFor(PhotoOwner.place, placeId),
    );

/// Used when a place points at a type that was hidden or removed.
const unknownPlaceType = PlaceType(
  id: '',
  name: 'Place',
  iconKey: 'place',
  kind: PlaceKind.shop,
);

PlaceType placeTypeFor(List<PlaceType> types, String typeId) {
  for (final t in types) {
    if (t.id == typeId) return t;
  }
  return unknownPlaceType;
}

/// A row of the place list: the place with its resolved type.
class PlaceEntry {
  const PlaceEntry(this.place, this.type);

  final Place place;
  final PlaceType type;
}

/// Search text and type filter of the place list.
class PlaceListFilter {
  const PlaceListFilter({this.query = '', this.typeId});

  final String query;
  final String? typeId;

  PlaceListFilter copyWith({
    String? query,
    String? typeId,
    bool clearType = false,
  }) => PlaceListFilter(
    query: query ?? this.query,
    typeId: clearType ? null : (typeId ?? this.typeId),
  );
}

class PlaceListFilterNotifier extends Notifier<PlaceListFilter> {
  @override
  PlaceListFilter build() => const PlaceListFilter();

  void setQuery(String query) => state = state.copyWith(query: query);

  /// Tapping the selected type again clears the filter.
  void toggleType(String typeId) => state = state.typeId == typeId
      ? state.copyWith(clearType: true)
      : state.copyWith(typeId: typeId);
}

final placeListFilterProvider =
    NotifierProvider.autoDispose<PlaceListFilterNotifier, PlaceListFilter>(
      PlaceListFilterNotifier.new,
    );

/// Pure filter used by [placeEntriesProvider]; accent-insensitive prefix match
/// on the name and address (DATA_MODEL § 6).
List<PlaceEntry> filterPlaceEntries(
  List<PlaceEntry> entries,
  PlaceListFilter filter,
) {
  final tokens = normalizeForSearch(filter.query)
      .split(' ')
      .where((t) => t.isNotEmpty)
      .toList();
  return [
    for (final e in entries)
      if ((filter.typeId == null || e.place.typeId == filter.typeId) &&
          _matches(e, tokens))
        e,
  ];
}

bool _matches(PlaceEntry e, List<String> tokens) {
  if (tokens.isEmpty) return true;
  final words = normalizeForSearch(
    '${e.place.name} ${e.place.address ?? ''} ${e.type.name}',
  ).split(' ');
  return tokens.every((t) => words.any((w) => w.startsWith(t)));
}

/// Places with their types, filtered by [placeListFilterProvider].
final placeEntriesProvider = Provider.autoDispose<AsyncValue<List<PlaceEntry>>>(
  (ref) {
    final places = ref.watch(placesProvider);
    final types = ref.watch(placeTypesProvider).value ?? const <PlaceType>[];
    final filter = ref.watch(placeListFilterProvider);
    return places.whenData(
      (list) => filterPlaceEntries([
        for (final p in list) PlaceEntry(p, placeTypeFor(types, p.typeId)),
      ], filter),
    );
  },
);

/// Writes that are not part of the form (delete from the list or the place page).
class PlaceActions {
  PlaceActions(this._ref);

  final Ref _ref;

  /// Soft delete. The place's prices and menu stay in the database.
  Future<void> delete(String id) =>
      _ref.read(placesRepositoryProvider).delete(id);
}

final placeActionsProvider = Provider<PlaceActions>(PlaceActions.new);
