import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../map/views/locate_radar.dart';
import '../../map/views/map_view.dart';
import '../../map/views/place_drop_pin.dart';
import '../view_models/address_search_view_model.dart';
import '../view_models/place_form_view_model.dart';

/// Full-screen map to set a place's location: tap to drop or move the pin, "I'm
/// here" (GPS), or search an address. Edits the open form directly; going back
/// keeps the pin.
///
/// Open it with `Navigator.of(context).push(LocationPickerScreen.route(placeId))`.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({super.key, required this.placeId});

  /// Key of the open form (`null` while adding a new place).
  final String? placeId;

  static Route<void> route(String? placeId) => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => LocationPickerScreen(placeId: placeId),
  );

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  static const _pinZoom = 17.0;

  /// About the height of the confirm panel, so Google's logo stays visible above it.
  static const _panelHeight = Chrome.minTouch * 4;

  final _map = MapViewController();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  PlaceFormNotifier get _form =>
      ref.read(placeFormProvider(widget.placeId).notifier);

  void _flyTo(double lat, double lng, {double? zoom}) {
    unawaited(
      _map.animateTo(
        LatLng(lat, lng),
        zoom: zoom ?? _map.zoom.clamp(_pinZoom - 2, mapMaxZoom),
      ),
    );
  }

  Future<void> _locate() async {
    final fix = await _form.useCurrentLocation();
    if (fix.isOk && mounted) _flyTo(fix.lat!, fix.lng!, zoom: _pinZoom);
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(placeFormProvider(widget.placeId));
    final search = ref.watch(addressSearchProvider);
    final draft = form.draft;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final insets = MediaQuery.paddingOf(context);

    final start = draft.hasLocation
        ? LatLng(draft.lat!, draft.lng!)
        : LatLng(defaultMapCenter.lat, defaultMapCenter.lng);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: PlaceDropPin(
              dropKey: '${draft.lat},${draft.lng}',
              position: draft.hasLocation
                  ? LatLng(draft.lat!, draft.lng!)
                  : null,
              builder: (context, markers) => MapView(
                MapViewConfig(
                  controller: _map,
                  initialTarget: start,
                  initialZoom: draft.hasLocation ? _pinZoom : defaultMapZoom,
                  // Keeps Google's logo above the confirm panel.
                  padding: EdgeInsets.only(
                    bottom: insets.bottom + _panelHeight,
                  ),
                  markers: markers,
                  onTap: (point) {
                    FocusScope.of(context).unfocus();
                    _form.setPosition(point.latitude, point.longitude);
                  },
                ),
              ),
            ),
          ),

          // Radar while GPS is working.
          if (form.locating)
            const Center(child: IgnorePointer(child: LocateRadar())),

          // Top: back + address search.
          Positioned(
            top: insets.top + Space.sm,
            left: Space.lg,
            right: Space.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _RoundGlassButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: GlassSurface(
                        height: Chrome.minTouch + Space.sm,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg,
                        ),
                        child: TextField(
                          controller: _search,
                          textDirection: null,
                          textInputAction: TextInputAction.search,
                          onChanged: ref
                              .read(addressSearchProvider.notifier)
                              .onQueryChanged,
                          onSubmitted: ref
                              .read(addressSearchProvider.notifier)
                              .search,
                          decoration: InputDecoration(
                            hintText: 'Search an address',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            suffixIcon: search.loading
                                ? const Padding(
                                    padding: EdgeInsets.all(Space.md),
                                    child: SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : (_search.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Clear',
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () {
                                            _search.clear();
                                            ref
                                                .read(
                                                  addressSearchProvider
                                                      .notifier,
                                                )
                                                .clear();
                                          },
                                        )),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (search.offline)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: GlassSurface(
                      borderRadius: Radii.cardR,
                      padding: const EdgeInsets.all(Space.lg),
                      child: Text(
                        "Can't search addresses right now. Tap the map to drop the pin.",
                        style: t.bodyMedium,
                      ),
                    ),
                  )
                else if (search.results.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: GlassSurface(
                      borderRadius: Radii.cardR,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final r in search.results)
                            InkWell(
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                _form.setPosition(
                                  r.lat,
                                  r.lng,
                                  address: r.displayName,
                                );
                                _flyTo(r.lat, r.lng, zoom: _pinZoom);
                                _search.clear();
                                ref
                                    .read(addressSearchProvider.notifier)
                                    .clear();
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: Chrome.minTouch,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.lg,
                                    vertical: Space.md,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.place_outlined,
                                        size: 20,
                                        color: c.muted,
                                      ),
                                      const SizedBox(width: Space.md),
                                      Expanded(
                                        child: Text(
                                          r.displayName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                else if (search.hasSearched && search.results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: GlassSurface(
                      borderRadius: Radii.cardR,
                      padding: const EdgeInsets.all(Space.lg),
                      child: Text(
                        'No address found. Tap the map to drop the pin.',
                        style: t.bodyMedium,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom: I'm here, and the confirm panel.
          Positioned(
            left: Space.lg,
            right: Space.lg,
            bottom: insets.bottom + Space.lg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Spacer(),
                    _RoundGlassButton(
                      icon: Icons.my_location_rounded,
                      label: "I'm here",
                      onTap: form.locating ? null : _locate,
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                GlassSurface(
                  borderRadius: Radii.cardR,
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        draft.hasLocation
                            ? (draft.address.isNotEmpty
                                  ? draft.address
                                  : _coords(draft.lat!, draft.lng!))
                            : 'Tap the map to drop the pin, or use "I\'m here".',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium,
                      ),
                      if (form.locationMessage != null) ...[
                        const SizedBox(height: Space.sm),
                        Text(
                          form.locationMessage!,
                          style: t.bodySmall?.copyWith(color: c.amber),
                        ),
                      ],
                      const SizedBox(height: Space.md),
                      Row(
                        children: [
                          if (draft.hasLocation)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _form.fillAddressFromPin,
                                child: const Text('Get address'),
                              ),
                            ),
                          if (draft.hasLocation)
                            const SizedBox(width: Space.md),
                          Expanded(
                            child: FilledButton(
                              onPressed: draft.hasLocation
                                  ? () => Navigator.of(context).maybePop()
                                  : null,
                              child: const Text('Use this location'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _coords(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        enabled: onTap != null,
        onTap: onTap,
        child: Squish(
          onTap: onTap,
          child: GlassSurface(
            child: SizedBox.square(
              dimension: Chrome.minTouch + Space.sm,
              child: Icon(icon, color: onTap == null ? c.muted : c.text),
            ),
          ),
        ),
      ),
    );
  }
}
