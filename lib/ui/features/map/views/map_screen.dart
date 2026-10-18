import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/place_logic/geo.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../places/view_models/place_launcher.dart';
import '../../places/view_models/places_providers.dart';
import '../../places/views/open_status_badge.dart';
import '../../places/views/place_icons.dart';
import '../view_models/map_location_view_model.dart';
import '../view_models/map_places.dart';
import '../view_models/map_price_pins.dart';
import 'map_controls.dart';
import 'map_view.dart';
import 'pin_layers.dart';
import 'route_line_layer.dart';

/// The Map tab: your places on a Google map,
/// price pins when search sends some, "I'm here" with a radar, and a line to a
/// place. Sits inside the shell, so overlays keep clear of the floating nav.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _controller = MapViewController();
  var _fitted = false;
  var _zoom = defaultMapZoom;
  String? _selectedId;
  ({LatLng from, LatLng to})? _route;

  void _fitPlaces(List<PlaceEntry> entries) {
    if (_fitted || entries.isEmpty) return;
    _fitted = true;
    unawaited(_controller.fit(_placePoints(entries), maxZoom: 16));
  }

  static List<LatLng> _placePoints(List<PlaceEntry> entries) => [
    for (final e in entries) LatLng(e.place.lat!, e.place.lng!),
  ];

  Future<void> _showRoute(PlaceEntry entry) async {
    final to = LatLng(entry.place.lat!, entry.place.lng!);
    var loc = ref.read(mapLocationProvider);
    if (!loc.hasPosition) {
      await ref.read(mapLocationProvider.notifier).locate();
      if (!mounted) return;
      loc = ref.read(mapLocationProvider);
    }
    if (!loc.hasPosition) return; // the message under the controls says why
    final from = LatLng(loc.lat!, loc.lng!);
    setState(() => _route = (from: from, to: to));
    unawaited(_controller.fit([from, to], maxZoom: 17));
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(mapPlacesProvider);
    final priceFocus = ref.watch(mapPricePinsProvider);
    final entries = places.value ?? const <PlaceEntry>[];
    final selected = entries
        .where((e) => e.place.id == _selectedId)
        .firstOrNull;
    final bottom = _bottomInset(context);

    _fitPlaces(entries);
    ref.listen(mapPlacesProvider, (_, next) {
      final list = next.value;
      if (list != null) _fitPlaces(list);
    });

    return Stack(
      children: [
        Positioned.fill(
          child: RouteDraw(
            route: _route,
            builder: (context, lines) => MapView(
              MapViewConfig(
                controller: _controller,
                padding: EdgeInsets.only(bottom: bottom),
                lines: lines,
                onZoomChanged: (z) {
                  if ((z - _zoom).abs() > 0.01) setState(() => _zoom = z);
                },
                onTap: (_) => setState(() {
                  _selectedId = null;
                  _route = null;
                }),
                markers: [
                  ...placeMarkers(
                    controller: _controller,
                    zoom: _zoom,
                    selectedId: _selectedId,
                    places: [
                      for (final e in entries)
                        PlaceMarkerData(
                          id: e.place.id,
                          name: e.place.name,
                          lat: e.place.lat!,
                          lng: e.place.lng!,
                          icon: placeTypeIcon(e.type.iconKey),
                        ),
                    ],
                    onTap: (p) => setState(() {
                      _selectedId = p.id;
                      _route = null;
                    }),
                  ),
                  if (priceFocus != null)
                    ...pricePinMarkers(
                      pins: priceFocus,
                      zoom: _zoom,
                      controller: _controller,
                      onPinTap: (pin) =>
                          context.push(Routes.placeDetail(pin.placeId)),
                    ),
                  ...userLocationMarkers(ref.watch(mapLocationProvider)),
                ],
              ),
            ),
          ),
        ),

        // Top: what the map is showing.
        Positioned(
          top: MediaQuery.paddingOf(context).top + Space.sm,
          left: Space.lg,
          right: Space.lg,
          child: Row(
            children: [
              Flexible(
                child: _StatusChip(
                  text: priceFocus != null
                      ? (priceFocus.length == 1
                            ? '1 price pin'
                            : '${priceFocus.length} price pins')
                      : (entries.isEmpty
                            ? 'No places on the map yet'
                            : (entries.length == 1
                                  ? '1 place'
                                  : '${entries.length} places')),
                  onClear: priceFocus == null
                      ? null
                      : ref.read(mapPricePinsProvider.notifier).clear,
                ),
              ),
              const SizedBox(width: Space.sm),
              MapGlassButton(
                icon: Icons.add_location_alt_outlined,
                label: 'Add a place',
                onTap: () => context.push(Routes.placeNew),
              ),
            ],
          ),
        ),

        // Bottom: selected place, then attribution + locate-me.
        Positioned(
          left: Space.lg,
          right: Space.lg,
          bottom: bottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected != null) ...[
                _SelectedPlaceCard(
                  entry: selected,
                  hasRoute: _route != null,
                  onOpen: () =>
                      context.push(Routes.placeDetail(selected.place.id)),
                  onRoute: () => _showRoute(selected),
                  onDirections: () async {
                    if (!await directionsToPlace(selected.place) &&
                        context.mounted) {
                      FloatingToast.show(
                        context,
                        'No maps app found',
                        kind: ToastKind.error,
                      );
                    }
                  },
                ),
                const SizedBox(height: Space.sm),
              ],
              const LocateMessage(),
              const SizedBox(height: Space.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Spacer(),
                  LocateMeControl(controller: _controller),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Keeps the overlays clear of the floating nav pill.
  double _bottomInset(BuildContext context) =>
      Chrome.contentBottomPadding -
      Space.xxl +
      Space.md +
      MediaQuery.paddingOf(context).bottom;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, this.onClear});

  final String text;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return GlassSurface(
      height: Chrome.minTouch + Space.sm,
      padding: EdgeInsets.only(
        left: Space.lg,
        right: onClear == null ? Space.lg : Space.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelLarge,
            ),
          ),
          if (onClear != null)
            IconButton(
              tooltip: 'Clear price pins',
              onPressed: onClear,
              icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
            ),
        ],
      ),
    );
  }
}

class _SelectedPlaceCard extends ConsumerWidget {
  const _SelectedPlaceCard({
    required this.entry,
    required this.hasRoute,
    required this.onOpen,
    required this.onRoute,
    required this.onDirections,
  });

  final PlaceEntry entry;
  final bool hasRoute;
  final VoidCallback onOpen;
  final VoidCallback onRoute;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final place = entry.place;
    final loc = ref.watch(mapLocationProvider);
    final away = loc.hasPosition
        ? haversineKm(loc.lat!, loc.lng!, place.lat!, place.lng!)
        : null;
    final meta = [
      entry.type.name,
      if (away != null)
        '${formatDistanceKm(away)} ${hasRoute ? 'in a straight line' : 'away'}',
    ].join(' · ');

    return GlassSurface(
      borderRadius: Radii.cardR,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium,
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall,
                    ),
                    if (place.openingHours != null)
                      OpenStatusBadge(hours: place.openingHours),
                  ],
                ),
              ),
              if (place.rating != null) ...[
                Icon(Icons.star_rounded, size: 16, color: c.text),
                const SizedBox(width: 2),
                Text('${place.rating}', style: t.labelMedium),
              ],
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRoute,
                  child: Text(hasRoute ? 'Redraw line' : 'Show line'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: onDirections,
                  child: const Text('Directions'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: FilledButton(
                  onPressed: onOpen,
                  child: const Text('Open'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
