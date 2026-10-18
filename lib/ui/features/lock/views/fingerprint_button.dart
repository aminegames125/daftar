import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import 'pin_entry.dart';

/// Motion fingerprint: while the system prompt is open, a lime trace sweeps up
/// through the fingerprint icon. Sits in the bottom-left slot of the keypad.
class FingerprintKey extends StatefulWidget {
  const FingerprintKey({
    super.key,
    required this.scanning,
    required this.onTap,
  });

  final bool scanning;
  final VoidCallback onTap;

  @override
  State<FingerprintKey> createState() => _FingerprintKeyState();
}

class _FingerprintKeyState extends State<FingerprintKey>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DaftarMotion.write,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FingerprintKey old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.scanning && !DaftarMotion.reduced(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = widget.scanning ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const iconSize = 34.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Semantics(
        button: true,
        label: 'Unlock with fingerprint',
        excludeSemantics: true,
        onTap: widget.onTap,
        child: Squish(
          onTap: widget.onTap,
          pressedScale: 0.92,
          child: SizedBox(
            width: PinPad.keySize,
            height: PinPad.keySize,
            child: Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = DaftarMotion.emphasized.transform(_c.value);
                  return Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      const Icon(Icons.fingerprint, size: iconSize),
                      ClipRect(
                        clipper: _BottomUpClipper(t),
                        child: Icon(
                          Icons.fingerprint,
                          size: iconSize,
                          color: c.accentText,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows only the bottom [fraction] of the child.
class _BottomUpClipper extends CustomClipper<Rect> {
  const _BottomUpClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, size.height * (1 - fraction), size.width, size.height);

  @override
  bool shouldReclip(_BottomUpClipper old) => old.fraction != fraction;
}
