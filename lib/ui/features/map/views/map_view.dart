import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import 'google_map_view.dart';
import 'map_markers.dart';

export 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

/// Default map centre when there is nothing else to show: Tunis.
// DECISION(owner): the map opens on Tunis until a place or the phone's position is known.
const defaultMapCenter = (lat: 36.8065, lng: 10.1815);
const defaultMapZoom = 12.0;

/// Zoom limits shared by every map.
const double mapMinZoom = 3;
const double mapMaxZoom = 19;

/// One marker on a [MapView]. The picture comes from [visual]; the real map
/// turns it into a cached bitmap (see `marker_bitmaps.dart`).
class MapMarkerSpec {
  const MapMarkerSpec({
    required this.id,
    required this.position,
    required this.visual,
    this.onTap,
    this.alpha = 1,
    this.zIndex = 0,
  });

  final String id;
  final LatLng position;
  final MarkerVisual visual;
  final VoidCallback? onTap;
  final double alpha;
  final int zIndex;
}

/// A straight line on a [MapView] (a route line gets its border from a wider
/// line drawn underneath).
class MapLineSpec {
  const MapLineSpec({
    required this.id,
    required this.points,
    required this.color,
    required this.width,
    this.zIndex = 0,
  });

  final String id;
  final List<LatLng> points;
  final Color color;
  final int width;
  final int zIndex;
}

/// Moves the camera of a [MapView]. Create one per screen and give it to the
/// [MapViewConfig]. A [fit] made before the map is ready runs as soon as it is;
/// an [animateTo] made before that is dropped.
class MapViewController {
  Future<void> Function(LatLng target, double? zoom)? _animateTo;
  Future<void> Function(List<LatLng> points, double maxZoom, double padding)?
  _fit;
  ({List<LatLng> points, double maxZoom, double padding})? _pendingFit;

  /// Last known zoom (updated when the camera stops).
  double zoom = defaultMapZoom;

  bool get isAttached => _animateTo != null;

  /// Fly to [target]; keeps the current zoom when [zoom] is null.
  Future<void> animateTo(LatLng target, {double? zoom}) async =>
      _animateTo?.call(target, zoom);

  /// Zoom so every point is visible.
  Future<void> fit(
    List<LatLng> points, {
    double maxZoom = 16,
    double padding = 72,
  }) async {
    if (points.isEmpty) return;
    final fit = _fit;
    if (fit == null) {
      _pendingFit = (points: points, maxZoom: maxZoom, padding: padding);
      return;
    }
    await fit(points, maxZoom, padding);
  }

  /// Used by map implementations.
  void attach({
    required Future<void> Function(LatLng target, double? zoom) animateTo,
    required Future<void> Function(
      List<LatLng> points,
      double maxZoom,
      double padding,
    )
    fit,
  }) {
    _animateTo = animateTo;
    _fit = fit;
    final pending = _pendingFit;
    _pendingFit = null;
    if (pending != null) {
      unawaited(
        this.fit(
          pending.points,
          maxZoom: pending.maxZoom,
          padding: pending.padding,
        ),
      );
    }
  }

  void detach() {
    _animateTo = null;
    _fit = null;
  }
}

/// Everything a map implementation needs. Plain data, so tests can replace the
/// real Google map with a placeholder (see [mapViewBuilderProvider]).
class MapViewConfig {
  const MapViewConfig({
    this.controller,
    this.initialTarget,
    this.initialZoom = defaultMapZoom,
    this.markers = const [],
    this.lines = const [],
    this.interactive = true,
    this.lite = false,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.onZoomChanged,
  });

  /// null for maps that are never moved by code (previews).
  final MapViewController? controller;
  final LatLng? initialTarget;
  final double initialZoom;

  final List<MapMarkerSpec> markers;
  final List<MapLineSpec> lines;

  /// false: no gestures at all (previews).
  final bool interactive;

  /// Android lite mode: a static bitmap map, cheap in lists.
  final bool lite;

  /// Map padding: keeps Google's logo clear of Daftar's own overlays.
  final EdgeInsets padding;
  final ValueChanged<LatLng>? onTap;

  /// Called when the camera stops moving.
  final ValueChanged<double>? onZoomChanged;

  LatLng get startTarget =>
      initialTarget ?? LatLng(defaultMapCenter.lat, defaultMapCenter.lng);
}

typedef MapViewBuilder = Widget Function(
  BuildContext context,
  MapViewConfig config,
);

/// The map implementation. The real one is the Google map
/// (`google_map_view.dart`); widget tests override this with a placeholder so
/// the platform view is never created.
final mapViewBuilderProvider = Provider<MapViewBuilder>(
  (ref) => _defaultBuilder,
);

Widget _defaultBuilder(BuildContext context, MapViewConfig config) {
  // Safety net: `flutter test` has no platform views.
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return const SizedBox.expand();
  }
  return GoogleMapView(config: config);
}

/// A map. It fills the space it is given.
class MapView extends ConsumerWidget {
  const MapView(this.config, {super.key});

  final MapViewConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(mapViewBuilderProvider)(context, config);
}
