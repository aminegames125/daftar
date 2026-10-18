import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';

/// Motion quantity roll: the number rolls up when it grows and down when it
/// shrinks, the old digits leaving the opposite way. Reduced motion swaps it.
class QuantityRoll extends StatefulWidget {
  const QuantityRoll({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  State<QuantityRoll> createState() => _QuantityRollState();
}

class _QuantityRollState extends State<QuantityRoll> {
  static final SpringCurve _spring = SpringCurve(DaftarMotion.spatial);
  bool _up = true;

  @override
  void didUpdateWidget(QuantityRoll old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _up = widget.value > old.value;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = DaftarMotion.reduced(context);
    final current = ValueKey<int>(widget.value);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : _spring.duration,
      reverseDuration: reduced ? Duration.zero : DaftarMotion.fast,
      transitionBuilder: (child, animation) {
        final incoming = child.key == current;
        final dy = incoming == _up ? 1.0 : -1.0;
        final slide = CurvedAnimation(
          parent: animation,
          curve: _spring,
          reverseCurve: DaftarMotion.standard,
        );
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, dy),
              end: Offset.zero,
            ).animate(slide),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, children: [...previous, ?current]),
      child: Text(
        '${widget.value}',
        key: current,
        style: widget.style,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Motion badge: a small count bubble that pops (springs in) when the count
/// changes and disappears at zero.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = DaftarMotion.reduced(context);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          top: -6,
          end: -6,
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: reduced ? Duration.zero : DaftarMotion.base,
              switchInCurve: DaftarMotion.pop,
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: count <= 0
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : _Bubble(key: ValueKey(count), count: count, scheme: scheme),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.count, required this.scheme});

  final int count;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: '$count in basket',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          count > 99 ? '99+' : '$count',
          maxLines: 1,
          style: t.labelSmall?.copyWith(
            color: scheme.onError,
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
