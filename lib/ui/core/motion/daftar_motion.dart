import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Motion tokens.
///
/// Rule: anything that *moves* uses a spring; fades and colour changes use
/// [standard]; the Dal stroke write-on uses [emphasized].
abstract final class DaftarMotion {
  /// Moves, sheets, nav changes. Slight overshoot, settles fast.
  static final SpringDescription spatial = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.73,
  );

  /// Playful pops: liquid nav pill, toasts, FAB menu, badges.
  static final SpringDescription bouncy = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 200,
    ratio: 0.55,
  );

  /// No-bounce settle for effects that must not overshoot.
  static final SpringDescription effects = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 1600,
    ratio: 1.0,
  );

  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve emphasized = Cubic(0.65, 0, 0.35, 1);
  static const Curve pop = Cubic(0.34, 1.56, 0.64, 1);

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  /// The Dal stroke writing itself.
  static const Duration write = Duration(milliseconds: 900);

  /// True when Android's "Remove animations" is on. Show the final frame.
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// A [Curve] that follows a spring from 0 to 1, for APIs that take curves
/// (AnimatedContainer, AnimatedAlign, ...). Pair it with [duration].
class SpringCurve extends Curve {
  SpringCurve(this.spring) : _sim = SpringSimulation(spring, 0, 1, 0) {
    _seconds = _settleTime(_sim);
  }

  final SpringDescription spring;
  final SpringSimulation _sim;
  late final double _seconds;

  static double _settleTime(SpringSimulation sim) {
    var t = 0.0;
    while (t < 3 && !sim.isDone(t)) {
      t += 0.01;
    }
    return t;
  }

  /// Approximate settle time; use it as the animation duration.
  Duration get duration => Duration(milliseconds: (_seconds * 1000).round());

  @override
  double transformInternal(double t) => t >= 1 ? 1 : _sim.x(t * _seconds);
}
