import 'package:flutter/material.dart';

import 'daftar_motion.dart';

/// Motion "Tap squish": the child presses in a touch and springs back.
/// Wrap every card and custom button with it.
///
/// ```dart
/// Squish(onTap: () => context.push(Routes.places), child: MyCard())
/// ```
class Squish extends StatefulWidget {
  const Squish({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale while the finger is down.
  final double pressedScale;

  /// When false the child is shown as is and taps are ignored.
  final bool enabled;

  @override
  State<Squish> createState() => _SquishState();
}

class _SquishState extends State<Squish> {
  static final SpringCurve _release = SpringCurve(DaftarMotion.bouncy);
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = DaftarMotion.reduced(context);
    final active =
        widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => _set(true) : null,
      onTapUp: active ? (_) => _set(false) : null,
      onTapCancel: active ? () => _set(false) : null,
      onTap: active ? widget.onTap : null,
      onLongPress: active ? widget.onLongPress : null,
      child: AnimatedScale(
        scale: _down && !reduced ? widget.pressedScale : 1,
        duration: reduced
            ? Duration.zero
            : (_down ? DaftarMotion.fast : _release.duration),
        curve: _down ? DaftarMotion.standard : _release,
        child: widget.child,
      ),
    );
  }
}
