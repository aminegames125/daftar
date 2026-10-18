import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router.dart';
import '../../../../../domain/models/place.dart';
import '../../../../../domain/search/normalize_for_search.dart';
import '../../../../../domain/use_cases/best_offer_scorer.dart';
import '../../../../../domain/use_cases/relative_time.dart';
import '../../../../../domain/use_cases/search_matcher.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';
import '../../../products/view_models/catalog_providers.dart';
import '../../view_models/user_location.dart';
import 'form_bits.dart';

/// A place with its distance from the user, nearest first (pure, for tests).
class PlaceChoice {
  const PlaceChoice(this.place, this.distanceKm);
  final Place place;
  final double? distanceKm;
}

/// Filters [places] by [query] (normalised, token prefix) and sorts them:
/// by match quality when searching, otherwise nearest first, then A→Z.
List<PlaceChoice> choosePlaces(
  Iterable<Place> places,
  String query,
  GeoPoint? from,
) {
  final q = SearchQuery(query);
  final ranked = <(PlaceChoice, int)>[];
  for (final place in places) {
    final rank = q.isEmpty
        ? 0
        : q.matchAny([
            normalizeForSearch('${place.name} ${place.address ?? ''}'),
          ])?.index;
    if (rank == null) continue;
    final km = from != null && place.hasLocation
        ? distanceKm(from.lat, from.lng, place.lat!, place.lng!)
        : null;
    ranked.add((PlaceChoice(place, km), rank));
  }
  ranked.sort((a, b) {
    final byRank = a.$2.compareTo(b.$2);
    if (byRank != 0) return byRank;
    final da = a.$1.distanceKm, db = b.$1.distanceKm;
    if (da != db) {
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    }
    return normalizeForSearch(a.$1.place.name)
        .compareTo(normalizeForSearch(b.$1.place.name));
  });
  return [for (final (choice, _) in ranked) choice];
}

/// Bottom sheet that lets the user pick the place a price was seen at.
Future<Place?> showPlacePicker(BuildContext context) {
  return showModalBottomSheet<Place>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PlacePickerSheet(),
  );
}

class _PlacePickerSheet extends ConsumerStatefulWidget {
  const _PlacePickerSheet();

  @override
  ConsumerState<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends ConsumerState<_PlacePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final places = ref.watch(allPlacesProvider);
    final here = ref.watch(userLocationProvider).value;
    final choices = choosePlaces(places.value ?? const [], _query, here);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Text('Where did you see it?', style: t.headlineSmall),
            ),
            const SizedBox(height: Space.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: TextField(
                autofocus: false,
                textDirection: null,
                onChanged: (v) => setState(() => _query = v),
                decoration: boardInput(context, hint: 'Search your places')
                    .copyWith(
                      prefixIcon: Icon(Icons.search_rounded, color: c.muted),
                    ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Flexible(
              child: choices.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Space.gutter),
                      child: Text(
                        places.isLoading
                            ? 'Loading…'
                            : (_query.isEmpty
                                  ? 'No places yet.'
                                  : 'No place matches “$_query”.'),
                        style: t.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.gutter,
                      ),
                      itemCount: choices.length,
                      itemBuilder: (context, i) {
                        final choice = choices[i];
                        final subtitle = [
                          if (choice.distanceKm != null)
                            formatKm(choice.distanceKm!),
                          ?choice.place.address,
                        ].join(' · ');
                        return Semantics(
                          container: true,
                          button: true,
                          label:
                              '${choice.place.name}${subtitle.isEmpty ? '' : ', $subtitle'}',
                          excludeSemantics: true,
                          child: InkWell(
                            borderRadius: Radii.inputR,
                            onTap: () =>
                                Navigator.of(context).pop(choice.place),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 58),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: c.raised,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.place_outlined,
                                      size: 20,
                                      color: c.text,
                                    ),
                                  ),
                                  const SizedBox(width: Space.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          choice.place.name,
                                          style: t.titleMedium?.copyWith(
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (subtitle.isNotEmpty)
                                          Text(
                                            subtitle,
                                            style: t.bodySmall?.copyWith(
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Space.lg,
              ),
              child: TextButton.icon(
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.push(Routes.placeNew);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add a new place'),
                style: TextButton.styleFrom(
                  foregroundColor: c.text,
                  minimumSize: const Size(0, Chrome.minTouch),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
