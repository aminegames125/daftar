import 'package:go_router/go_router.dart';

import '../../ui/features/menus/views/menu_snap_screen.dart';
import '../../ui/features/places/views/place_detail_screen.dart';
import '../../ui/features/places/views/place_form_screen.dart';
import '../../ui/features/places/views/place_list_screen.dart';
import '../router.dart';

/// Full-screen routes for places and menus (places, menu snap).
///
/// `/places/new` must come before `/places/:id` so "new" is not read as an id.
final List<RouteBase> placesRoutes = [
  GoRoute(path: Routes.places, builder: (_, _) => const PlaceListScreen()),
  GoRoute(
    path: Routes.placeNew,
    builder: (_, state) =>
        PlaceFormScreen(importText: state.uri.queryParameters['import']),
  ),
  GoRoute(
    path: '/places/:id/edit',
    builder: (_, state) => PlaceFormScreen(placeId: state.pathParameters['id']),
  ),
  GoRoute(
    path: '/places/:id',
    builder: (_, state) =>
        PlaceDetailScreen(placeId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: Routes.menuSnap,
    builder: (_, state) =>
        MenuSnapScreen(placeId: state.uri.queryParameters['placeId']),
  ),
];
