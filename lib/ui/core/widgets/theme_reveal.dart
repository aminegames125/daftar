import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/daftar_motion.dart';

/// A snapshot of the old theme and where the new one starts spreading from.
class RevealFrame {
  const RevealFrame({required this.image, required this.origin});
  final ui.Image image;
  final Offset origin;
}

/// Drives motion "Theme reveal": the new theme spreads out in a circle from
/// the control that was tapped. Shared by [ThemeRevealHost] (which draws it) and
/// the settings screen (which starts it).
class ThemeRevealController {
  /// Marks the part of the app that is captured.
  final GlobalKey boundaryKey = GlobalKey();

  /// The running reveal, or null.
  final ValueNotifier<RevealFrame?> frame = ValueNotifier(null);

  /// Runs [apply] (the theme change) with a circular reveal starting at [origin]
  /// (global coordinates). Without a captured frame (reduced motion, tests, no
  /// boundary yet) it simply applies the change.
  Future<void> run({
    required Offset origin,
    required Future<void> Function() apply,
    required bool animate,
  }) async {
    if (!animate || frame.value != null) return apply();
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return apply();

    ui.Image? image;
    try {
      final ratio = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      image = await object
          .toImage(pixelRatio: ratio)
          .timeout(DaftarMotion.slow);
    } catch (_) {
      image = null;
    }
    if (image == null) return apply();
    frame.value = RevealFrame(image: image, origin: origin);
    await apply();
  }

  void dispose() => frame.dispose();
}

final themeRevealProvider = Provider<ThemeRevealController>((ref) {
  final controller = ThemeRevealController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Wraps the whole app: captures it for [ThemeRevealController] and draws the
/// reveal on top. Place it as high as possible (`MaterialApp.builder`).
class ThemeRevealHost extends StatelessWidget {
  const ThemeRevealHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final ThemeRevealController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: controller.boundaryKey, child: child),
        ValueListenableBuilder<RevealFrame?>(
          valueListenable: controller.frame,
          builder: (context, frame, _) {
            if (frame == null) return const SizedBox.shrink();
            return Positioned.fill(
              child: _RevealOverlay(
                key: ValueKey(frame),
                frame: frame,
                onDone: () {
                  controller.frame.value = null;
                  frame.image.dispose();
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RevealOverlay extends StatefulWidget {
  const _RevealOverlay({super.key, required this.frame, required this.onDone});

  final RevealFrame frame;
  final VoidCallback onDone;

  @override
  State<_RevealOverlay> createState() => _RevealOverlayState();
}

class _RevealOverlayState extends State<_RevealOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DaftarMotion.write,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: DaftarMotion.emphasized,
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) => ClipPath(
          clipper: CircleHoleClipper(
            center: widget.frame.origin,
            progress: _t.value,
          ),
          child: RawImage(image: widget.frame.image, fit: BoxFit.fill),
        ),
      ),
    );
  }
}

/// Clips away a growing circle: what is left is the "old theme" snapshot, and the
/// hole shows the new theme underneath. At `progress == 1` nothing is left.
class CircleHoleClipper extends CustomClipper<Path> {
  const CircleHoleClipper({required this.center, required this.progress});

  final Offset center;

  /// 0 = no hole, 1 = the hole covers the whole area.
  final double progress;

  /// Radius at which a circle at [center] covers a [size] rectangle completely.
  static double coverRadius(Offset center, Size size) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    return corners.map((c) => (c - center).distance).reduce(math.max);
  }

  @override
  Path getClip(Size size) {
    final radius = coverRadius(center, size) * progress;
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldReclip(CircleHoleClipper old) =>
      old.progress != progress || old.center != center;
}
