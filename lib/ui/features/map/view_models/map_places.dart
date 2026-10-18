import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/lookups.dart';
import '../../places/view_models/places_providers.dart';

/// Places that have a location, with their types, for the Map tab.
final mapPlacesProvider = Provider.autoDispose<AsyncValue<List<PlaceEntry>>>((
  ref,
) {
  final places = ref.watch(placesProvider);
  final types = ref.watch(placeTypesProvider).value ?? const <PlaceType>[];
  return places.whenData(
    (list) => [
      for (final p in list)
        if (p.hasLocation) PlaceEntry(p, placeTypeFor(types, p.typeId)),
    ],
  );
});
