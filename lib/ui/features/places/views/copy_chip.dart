import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';

/// Copy button: the copy icon turns into a check and the button
/// goes lime for a moment ("Copied"). Copies [value] to the clipboard.
class CopyChip extends StatefulWidget {
  const CopyChip({
    super.key,
    required this.value,
    this.label = 'Copy',
    this.copiedLabel = 'Copied',
    this.onCopied,
  });

  final String value;
  final String label;
  final String copiedLabel;
  final VoidCallback? onCopied;

  @override
  State<CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<CopyChip> {
  static const _resetAfter = Duration(milliseconds: 1600);
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    unawaited(HapticFeedback.mediumImpact());
    widget.onCopied?.call();
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(_resetAfter, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final duration = DaftarMotion.reduced(context)
        ? Duration.zero
        : DaftarMotion.base;
    final fg = _copied ? c.onLime : c.text;

    return Semantics(
      button: true,
      label: _copied ? widget.copiedLabel : widget.label,
      excludeSemantics: true,
      onTap: _copy,
      child: Squish(
        onTap: _copy,
        child: AnimatedContainer(
          duration: duration,
          curve: DaftarMotion.standard,
          constraints: const BoxConstraints(
            minHeight: Chrome.minTouch,
            minWidth: Chrome.minTouch,
          ),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: _copied ? c.lime : c.raised,
            borderRadius: Radii.pillR,
            border: Border.all(color: _copied ? c.lime : c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: CurvedAnimation(parent: anim, curve: DaftarMotion.pop),
                  child: RotationTransition(
                    turns: Tween(begin: 0.25, end: 0.0).animate(anim),
                    child: child,
                  ),
                ),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  key: ValueKey(_copied),
                  size: 18,
                  color: fg,
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                _copied ? widget.copiedLabel : widget.label,
                style: t.labelMedium?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
