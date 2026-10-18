import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'daftar_motion.dart';

/// A phone orientation sample, each axis in -1..1 (0 = at rest). Positive [x]
/// means the phone's right edge is tipped down, positive [y] its top edge is
/// tipped away from you.
class TiltReading {
  const TiltReading(this.x, this.y);
  final double x;
  final double y;
}

/// Turns raw accelerometer samples (m/s², gravity included) into [TiltReading]s,
/// relative to a slowly-adapting resting pose so it works however the phone is held.
class TiltFilter {
  TiltFilter({this.range = 4.0, this.smoothing = 0.2, this.restAdapt = 0.01});

  /// Acceleration difference (m/s²) that counts as a full tilt.
  final double range;

  /// 0..1 – how quickly the output follows the input.
  final double smoothing;

  /// 0..1 – how quickly the "rest" pose follows the phone's current pose.
  final double restAdapt;

  double? _restX;
  double? _restY;
  double _x = 0;
  double _y = 0;

  TiltReading add(double accelX, double accelY) {
    _restX ??= accelX;
    _restY ??= accelY;
    _restX = _restX! + (accelX - _restX!) * restAdapt;
    _restY = _restY! + (accelY - _restY!) * restAdapt;
    // Phone tipped right → gravity's x component drops, so invert.
    final targetX = (-(accelX - _restX!) / range).clamp(-1.0, 1.0);
    final targetY = ((accelY - _restY!) / range).clamp(-1.0, 1.0);
    _x += (targetX - _x) * smoothing;
    _y += (targetY - _y) * smoothing;
    return TiltReading(_x, _y);
  }
}

/// Motion tilt: leans its child toward the way the phone is tipped, like a
/// card catching the light. Does nothing when "Remove animations" is on or the
/// device has no accelerometer.
///
/// ```dart
/// Tilt(child: WalletStack(...))
/// ```
class Tilt extends StatefulWidget {
  const Tilt({
    super.key,
    required this.child,
    this.maxAngle = 0.1,
    this.readings,
  });

  final Widget child;

  /// Largest lean in radians (about 6°).
  final double maxAngle;

  /// Source of readings. Defaults to the device accelerometer; tests inject a stream.
  final Stream<TiltReading>? readings;

  @override
  State<Tilt> createState() => _TiltState();
}

class _TiltState extends State<Tilt> {
  final ValueNotifier<TiltReading> _tilt = ValueNotifier(
    const TiltReading(0, 0),
  );
  StreamSubscription<TiltReading>? _sub;
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only listen while visible (tabs that are not showing have their tickers off)
    // and when animations are allowed.
    final shouldListen =
        TickerMode.valuesOf(context).enabled && !DaftarMotion.reduced(context);
    if (shouldListen == _listening) return;
    _listening = shouldListen;
    unawaited(_sub?.cancel());
    _sub = null;
    if (shouldListen) {
      _subscribe();
    } else {
      _tilt.value = const TiltReading(0, 0);
    }
  }

  void _subscribe() {
    try {
      final stream = widget.readings ?? _deviceReadings();
      _sub = stream.listen(
        (r) => _tilt.value = r,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // No sensor support on this device: stay flat.
    }
  }

  static Stream<TiltReading> _deviceReadings() {
    final filter = TiltFilter();
    return accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .map((e) => filter.add(e.x, e.y));
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _tilt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TiltReading>(
      valueListenable: _tilt,
      child: widget.child,
      builder: (context, r, child) {
        if (r.x == 0 && r.y == 0) return child!;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateX(-r.y * widget.maxAngle)
            ..rotateY(r.x * widget.maxAngle),
          child: child,
        );
      },
    );
  }
}
