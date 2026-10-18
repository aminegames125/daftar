import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/models/map_pin.dart';
import '../../../../domain/place_logic/pin_clustering.dart';
import 'map_markers.dart';
import 'map_view.dart';

/// Size of one grid cell used to merge nearby pins, in screen pixels.
const double clusterCellPx = 64;

/// Zooms the camera so all [points] are visible (used when a cluster is tapped).
void zoomToPoints(MapViewController controller, List<LatLng> points) {
  HapticFeedback.selectionClick();
  if (points.length < 2) return;
  unawaited(controller.fit(points, maxZoom: 18));
}

/// Price pins with merge / split by zoom, as map markers. The
/// clustering is Daftar's own (`clusterByGrid`); the caller passes the current
/// [zoom] (from `MapViewConfig.onZoomChanged`). Best pins are drawn on top.
List<MapMarkerSpec> pricePinMarkers({
  required List<MapPin> pins,
  required double zoom,
  required MapViewController controller,
  ValueChanged<MapPin>? onPinTap,
  String? selectedPlaceId,
}) {
  final clusters = clusterByGrid<MapPin>(
    pins,
    lat: (p) => p.lat,
    lng: (p) => p.lng,
    zoom: zoom,
    cellPx: clusterCellPx,
  );
  return [
    for (final cluster in clusters)
      if (cluster.isSingle)
        MapMarkerSpec(
          id: 'pin:${cluster.first.placeId}:${cluster.first.label}',
          position: LatLng(cluster.first.lat, cluster.first.lng),
          visual: PricePinVisual(
            cluster.first,
            selected: cluster.first.placeId == selectedPlaceId,
          ),
          alpha: cluster.first.isStale ? 0.4 : 1,
          zIndex: cluster.first.isBest ? 2 : 0,
          onTap: onPinTap == null ? null : () => onPinTap(cluster.first),
        )
      else
        MapMarkerSpec(
          id: 'cluster:${cluster.members.map((p) => p.placeId).join(',')}',
          position: LatLng(cluster.lat, cluster.lng),
          visual: ClusterVisual(
            count: cluster.members.length,
            hasBest: cluster.members.any((p) => p.isBest),
          ),
          zIndex: cluster.members.any((p) => p.isBest) ? 2 : 1,
          onTap: () => zoomToPoints(controller, [
            for (final p in cluster.members) LatLng(p.lat, p.lng),
          ]),
        ),
  ];
}

/// A place to draw as a round icon marker.
class PlaceMarkerData {
  const PlaceMarkerData({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.icon,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final IconData icon;
}

/// Saved places as icon markers, merged when they are close.
List<MapMarkerSpec> placeMarkers({
  required List<PlaceMarkerData> places,
  required double zoom,
  required MapViewController controller,
  ValueChanged<PlaceMarkerData>? onTap,
  String? selectedId,
}) {
  final clusters = clusterByGrid<PlaceMarkerData>(
    places,
    lat: (p) => p.lat,
    lng: (p) => p.lng,
    zoom: zoom,
    cellPx: clusterCellPx,
  );
  return [
    for (final cluster in clusters)
      if (cluster.isSingle)
        MapMarkerSpec(
          id: 'place:${cluster.first.id}',
          position: LatLng(cluster.first.lat, cluster.first.lng),
          visual: PlaceVisual(
            icon: cluster.first.icon,
            label: cluster.first.name,
            selected: cluster.first.id == selectedId,
          ),
          zIndex: cluster.first.id == selectedId ? 3 : 0,
          onTap: onTap == null ? null : () => onTap(cluster.first),
        )
      else
        MapMarkerSpec(
          id: 'placegroup:${cluster.members.map((p) => p.id).join(',')}',
          position: LatLng(cluster.lat, cluster.lng),
          visual: ClusterVisual(count: cluster.members.length),
          zIndex: 1,
          onTap: () => zoomToPoints(controller, [
            for (final p in cluster.members) LatLng(p.lat, p.lng),
          ]),
        ),
  ];
}
