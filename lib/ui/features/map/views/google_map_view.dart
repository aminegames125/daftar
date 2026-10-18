import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_dark_style.dart';
import 'map_markers.dart';
import 'map_view.dart';
import 'marker_bitmaps.dart';

/// The real map: `google_maps_flutter` (Android). Markers are Daftar's own
/// pictures drawn once into bitmaps (see [MarkerBitmaps]); the dark theme uses a
/// style JSON; Google's logo stays visible (use [MapViewConfig.padding] to keep
/// it clear of overlays).
///
/// Never created under `flutter test`: tests override [mapViewBuilderProvider].
class GoogleMapView extends StatefulWidget {
  const GoogleMapView({super.key, required this.config});

  final MapViewConfig config;

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

/// One cache for the whole app, so a price pin is drawn once.
final _bitmaps = MarkerBitmaps();

class _GoogleMapViewState extends State<GoogleMapView> {
  GoogleMapController? _map;
  final _pending = <String>{};

  MapViewConfig get _config => widget.config;

  @override
  void didUpdateWidget(GoogleMapView old) {
    super.didUpdateWidget(old);
    if (old.config.controller != _config.controller) {
      old.config.controller?.detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _config.controller?.detach();
    _map = null;
    super.dispose();
  }

  void _attach() {
    _config.controller?.attach(animateTo: _animateTo, fit: _fit);
  }

  Future<void> _animateTo(LatLng target, double? zoom) async {
    final c = _map;
    if (c == null) return;
    final update = zoom == null
        ? CameraUpdate.newLatLng(target)
        : CameraUpdate.newLatLngZoom(target, zoom);
    try {
      await (_config.lite ? c.moveCamera(update) : c.animateCamera(update));
    } catch (e) {
      debugPrint('Map camera move failed: $e');
    }
  }

  Future<void> _fit(List<LatLng> points, double maxZoom, double padding) async {
    final c = _map;
    if (c == null || points.isEmpty) return;
    final south = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final north = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final west = points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final east = points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    final single = south == north && west == east;
    try {
      if (single) {
        await c.animateCamera(
          CameraUpdate.newLatLngZoom(points.first, maxZoom),
        );
        return;
      }
      final bounds = LatLngBounds(
        southwest: LatLng(south, west),
        northeast: LatLng(north, east),
      );
      await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
      final zoom = await c.getZoomLevel();
      if (zoom > maxZoom) await c.animateCamera(CameraUpdate.zoomTo(maxZoom));
    } catch (e) {
      // The map has no size yet, or was disposed while moving.
      debugPrint('Map fit failed: $e');
    }
  }

  void _onCreated(GoogleMapController controller) {
    _map = controller;
    // After the first layout: bounds need the map's size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attach();
    });
  }

  Future<void> _onIdle() async {
    final c = _map;
    if (c == null) return;
    try {
      final zoom = await c.getZoomLevel();
      if (!mounted) return;
      _config.controller?.zoom = zoom;
      _config.onZoomChanged?.call(zoom);
    } catch (e) {
      debugPrint('Map zoom read failed: $e');
    }
  }

  Set<Marker> _markers(MarkerPalette palette, double ratio) {
    final out = <Marker>{};
    for (final spec in _config.markers) {
      final icon = _bitmaps.peek(spec.visual, palette, ratio);
      if (icon == null) {
        _draw(spec.visual, palette, ratio);
        continue;
      }
      out.add(
        Marker(
          markerId: MarkerId(spec.id),
          position: spec.position,
          icon: icon,
          anchor: spec.visual.anchor,
          alpha: spec.alpha,
          zIndexInt: spec.zIndex,
          consumeTapEvents: true,
          onTap: spec.onTap,
        ),
      );
    }
    return out;
  }

  void _draw(MarkerVisual visual, MarkerPalette palette, double ratio) {
    final key = '${visual.cacheKey}|${palette.key}|$ratio';
    if (!_pending.add(key)) return;
    _bitmaps
        .load(visual, palette, ratio)
        .then((_) {
          _pending.remove(key);
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          debugPrint('Marker bitmap failed: $e');
        });
  }

  Set<Polyline> get _lines => {
    for (final line in _config.lines)
      Polyline(
        polylineId: PolylineId(line.id),
        points: line.points,
        color: line.color,
        width: line.width,
        zIndex: line.zIndex,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = MarkerPalette.of(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final interactive = _config.interactive && !_config.lite;
    final start = _config.startTarget;

    final map = GoogleMap(
      initialCameraPosition: CameraPosition(
        target: start,
        zoom: _config.initialZoom,
      ),
      style: dark ? darkMapStyle : null,
      liteModeEnabled: _config.lite,
      padding: _config.padding,
      minMaxZoomPreference: const MinMaxZoomPreference(mapMinZoom, mapMaxZoom),
      markers: _markers(palette, ratio),
      polylines: _lines,
      onMapCreated: _onCreated,
      onTap: _config.onTap,
      onCameraIdle: _config.onZoomChanged == null ? null : _onIdle,
      // Daftar draws its own controls; Google's logo stays.
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      myLocationEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: interactive,
      zoomGesturesEnabled: interactive,
    );
    return _config.interactive ? map : IgnorePointer(child: map);
  }
}
