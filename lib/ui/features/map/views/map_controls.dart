import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/glass_surface.dart';
import '../view_models/map_location_view_model.dart';
import 'locate_radar.dart';
import 'map_markers.dart';
import 'map_view.dart';

/// Round glass button for map overlays (locate me, close, ...). Glass is allowed
/// here: map overlays are floating surfaces.
class MapGlassButton extends StatelessWidget {
  const MapGlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Shows the icon in the accent colour (e.g. the phone's position is known).
  final bool active;

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
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: GlassSurface(
            child: SizedBox.square(
              dimension: Chrome.minTouch + Space.sm,
              child: Icon(
                icon,
                color: onTap == null
                    ? c.muted
                    : (active ? c.accentText : c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's position as a dot marker (none until a position is known).
List<MapMarkerSpec> userLocationMarkers(MapLocationState loc) {
  if (!loc.hasPosition) return const [];
  return [
    MapMarkerSpec(
      id: 'user-location',
      position: LatLng(loc.lat!, loc.lng!),
      visual: const UserDotVisual(),
      zIndex: 4,
    ),
  ];
}

/// Locate-me wiring shared by both maps: a button, the radar while GPS works
///, the message when it fails, and flying the camera to the first fix.
///
/// Place this *outside* the map in a `Stack` and give it the same
/// [MapViewController].
class LocateMeControl extends ConsumerStatefulWidget {
  const LocateMeControl({super.key, required this.controller, this.zoom = 16});

  final MapViewController controller;
  final double zoom;

  @override
  ConsumerState<LocateMeControl> createState() => _LocateMeControlState();
}

class _LocateMeControlState extends ConsumerState<LocateMeControl> {
  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(mapLocationProvider);

    ref.listen(mapLocationProvider.select((s) => s.ticket), (previous, next) {
      final s = ref.read(mapLocationProvider);
      if (s.hasPosition && next != previous) {
        unawaited(
          widget.controller.animateTo(
            LatLng(s.lat!, s.lng!),
            zoom: widget.zoom,
          ),
        );
      }
    });

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // The radar overflows the button's box and is centred on it.
        if (loc.locating)
          const Positioned.fill(
            child: IgnorePointer(
              child: OverflowBox(
                maxWidth: 160,
                maxHeight: 160,
                child: LocateRadar(),
              ),
            ),
          ),
        MapGlassButton(
          icon: loc.hasPosition
              ? Icons.my_location_rounded
              : Icons.location_searching_rounded,
          label: "I'm here",
          active: loc.hasPosition,
          onTap: loc.locating
              ? null
              : () => ref.read(mapLocationProvider.notifier).locate(),
        ),
      ],
    );
  }
}

/// Message under the controls when locating failed. Dismisses itself on tap.
class LocateMessage extends ConsumerWidget {
  const LocateMessage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(mapLocationProvider.select((s) => s.message));
    if (message == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: ref.read(mapLocationProvider.notifier).clearMessage,
      child: GlassSurface(
        borderRadius: Radii.cardR,
        padding: const EdgeInsets.all(Space.lg),
        child: Text(message, style: t.bodyMedium),
      ),
    );
  }
}
