import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'daftar_motion.dart';

/// Motion "Error shake": a short damped shake whenever [trigger] changes.
///
/// Keep an `int errorCount` in your state, increment it when validation
/// fails, and pass it as [trigger]. Nothing shakes on the first build. With
/// "Remove animations" on, the shake is skipped (colour changes should still
/// show the error).
///
/// ```dart
/// Shake(trigger: errorCount, child: MyField())
/// ```
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  // Motion shape constants, local to this effect.
  static const double _amplitude = 10;
  static const double _wiggles = 4;
  static const double _decay = 3.5;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DaftarMotion.slow,
  );

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !DaftarMotion.reduced(context)) {
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
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final dx =
            _amplitude *
            math.exp(-_decay * t) *
            math.sin(t * _wiggles * 2 * math.pi);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}
