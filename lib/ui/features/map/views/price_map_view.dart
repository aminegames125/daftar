import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/map_pin.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/map_location_view_model.dart';
import 'map_controls.dart';
import 'map_view.dart';
import 'pin_layers.dart';

/// A map of price pins, for the List / Map toggle of search results (and anywhere
/// else a set of [MapPin]s should be seen on the map).
///
/// * Best = lime glow, stale = faded, promo = amber outline; pins merge and split
///   with the zoom.
/// * Shows a Google map (dark style in the dark theme, Google's logo stays
///   visible), the phone's position and a locate-me button.
/// * Fits the camera to the pins whenever the set changes.
/// * It fills the space it is given: wrap it in an `Expanded` / `SizedBox`.
///
/// Tapping a pin calls [onPinTap]; by default it opens that place's page
/// (`Routes.placeDetail`).
///
/// ```dart
/// Expanded(child: PriceMapView(pins: pins, bottomInset: Chrome.contentBottomPadding))
/// ```
class PriceMapView extends ConsumerStatefulWidget {
  const PriceMapView({
    super.key,
    required this.pins,
    this.onPinTap,
    this.selectedPlaceId,
    this.bottomInset = Chrome.contentBottomPadding,
    this.showLocateButton = true,
  });

  final List<MapPin> pins;
  final ValueChanged<MapPin>? onPinTap;

  /// Highlights the pin of this place.
  final String? selectedPlaceId;

  /// Space the overlays (locate button) keep from the bottom edge so the nav
  /// does not cover them. Google's logo is lifted by the same amount.
  final double bottomInset;
  final bool showLocateButton;

  @override
  ConsumerState<PriceMapView> createState() => _PriceMapViewState();
}

class _PriceMapViewState extends ConsumerState<PriceMapView> {
  final _controller = MapViewController();
  double _zoom = defaultMapZoom;
  late String _fittedFor = _signature(widget.pins);

  static String _signature(List<MapPin> pins) =>
      pins.map((p) => '${p.placeId}@${p.lat},${p.lng}').join('|');

  static List<LatLng> _points(List<MapPin> pins) => [
    for (final p in pins) LatLng(p.lat, p.lng),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_controller.fit(_points(widget.pins), padding: _fitPadding));
  }

  @override
  void didUpdateWidget(PriceMapView old) {
    super.didUpdateWidget(old);
    final sig = _signature(widget.pins);
    if (sig != _fittedFor) {
      _fittedFor = sig;
      unawaited(_controller.fit(_points(widget.pins), padding: _fitPadding));
    }
  }

  static const _fitPadding = 72.0;

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(mapLocationProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: MapView(
            MapViewConfig(
              controller: _controller,
              initialZoom: defaultMapZoom,
              padding: EdgeInsets.only(bottom: widget.bottomInset),
              onZoomChanged: (z) {
                if ((z - _zoom).abs() > 0.01) setState(() => _zoom = z);
              },
              markers: [
                ...pricePinMarkers(
                  pins: widget.pins,
                  zoom: _zoom,
                  controller: _controller,
                  selectedPlaceId: widget.selectedPlaceId,
                  onPinTap:
                      widget.onPinTap ??
                      (pin) => context.push(Routes.placeDetail(pin.placeId)),
                ),
                ...userLocationMarkers(loc),
              ],
            ),
          ),
        ),
        Positioned(
          left: Space.lg,
          right: Space.lg,
          bottom: widget.bottomInset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showLocateButton) const LocateMessage(),
              const SizedBox(height: Space.sm),
              if (widget.showLocateButton)
                Align(
                  alignment: Alignment.bottomRight,
                  child: LocateMeControl(controller: _controller),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
