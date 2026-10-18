import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';

/// Motion shimmer text: a soft light sweeps across the words while something
/// loads ("Searching…"). With "Remove animations" on it is plain muted text.
class ShimmerText extends StatefulWidget {
  const ShimmerText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DaftarMotion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = (widget.style ?? Theme.of(context).textTheme.bodyMedium)!
        .copyWith(color: c.muted);
    if (DaftarMotion.reduced(context)) return Text(widget.text, style: style);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          final t = _controller.value;
          return LinearGradient(
            colors: [c.muted, c.text, c.muted],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(-1.5 + 3 * t, 0),
            end: Alignment(-0.5 + 3 * t, 0),
          ).createShader(bounds);
        },
        child: child,
      ),
      child: Text(widget.text, style: style),
    );
  }
}
