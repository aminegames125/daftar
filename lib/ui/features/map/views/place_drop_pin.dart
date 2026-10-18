import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import 'map_markers.dart';
import 'map_view.dart';

/// The marker for a place being saved or moved, with its "Place drop" reveal
///. A Google marker is a bitmap and cannot fall, so the pin fades
/// in whenever [dropKey] changes; with reduced motion it just appears.
///
/// [builder] receives the pin as a one-item marker list to put on the map.
class PlaceDropPin extends StatefulWidget {
  const PlaceDropPin({
    super.key,
    required this.dropKey,
    required this.position,
    required this.builder,
    this.animate = true,
  });

  /// Any value; a new one replays the reveal.
  final Object dropKey;
  final LatLng? position;
  final bool animate;
  final Widget Function(BuildContext context, List<MapMarkerSpec> markers)
  builder;

  @override
  State<PlaceDropPin> createState() => _PlaceDropPinState();
}

class _PlaceDropPinState extends State<PlaceDropPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DaftarMotion.base,
    value: 1,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _play();
  }

  @override
  void didUpdateWidget(PlaceDropPin old) {
    super.didUpdateWidget(old);
    if (old.dropKey != widget.dropKey) _play();
  }

  void _play() {
    if (!widget.animate || DaftarMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => widget.builder(context, [
        if (position != null)
          MapMarkerSpec(
            id: 'drop-pin',
            position: position,
            visual: const DropPinVisual(),
            alpha: DaftarMotion.standard.transform(_c.value),
            zIndex: 5,
          ),
      ]),
    );
  }
}
