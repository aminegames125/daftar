import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import 'map_view.dart';

/// Builds a line from [from] to [to] that draws itself (motion "Route
/// draw"), as map lines for [builder]. With no [route] the builder gets an
/// empty list.
///
/// It is the straight line between the two points, not a street route: Daftar
/// has no routing service (a paid / rate-limited network call). Use "Directions"
/// to hand off to a maps app for turn-by-turn.
class RouteDraw extends StatefulWidget {
  const RouteDraw({super.key, required this.route, required this.builder});

  final ({LatLng from, LatLng to})? route;
  final Widget Function(BuildContext context, List<MapLineSpec> lines) builder;

  @override
  State<RouteDraw> createState() => _RouteDrawState();
}

class _RouteDrawState extends State<RouteDraw>
    with SingleTickerProviderStateMixin {
  static const _drawTime = Duration(milliseconds: 900);
  static const _lineWidth = 5;
  static const _borderWidth = 9;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _drawTime,
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
  void didUpdateWidget(RouteDraw old) {
    super.didUpdateWidget(old);
    if (old.route != widget.route && widget.route != null) _play();
  }

  void _play() {
    if (DaftarMotion.reduced(context)) {
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
    final route = widget.route;
    if (route == null) return widget.builder(context, const []);
    final c = context.colors;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = DaftarMotion.emphasized.transform(_c.value);
        final end = LatLng(
          route.from.latitude + (route.to.latitude - route.from.latitude) * t,
          route.from.longitude +
              (route.to.longitude - route.from.longitude) * t,
        );
        final points = [route.from, end];
        return widget.builder(context, [
          // Google polylines have no border: a wider line underneath.
          MapLineSpec(
            id: 'route-border',
            points: points,
            color: c.background,
            width: _borderWidth,
          ),
          MapLineSpec(
            id: 'route',
            points: points,
            color: c.lime,
            width: _lineWidth,
            zIndex: 1,
          ),
        ]);
      },
    );
  }
}
