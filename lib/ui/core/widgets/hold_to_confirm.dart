import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/daftar_motion.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';

/// Motion hold to confirm: press and hold, a fill sweeps across the button,
/// and only when it is full does [onConfirmed] fire. Releasing early drains it back.
/// Use it for anything that hides or deletes user data.
///
/// Screen-reader users get a normal long-press action instead of a timed hold.
///
/// ```dart
/// HoldToConfirm(label: 'Hold to hide', onConfirmed: () => repo.delete(id))
/// ```
class HoldToConfirm extends StatefulWidget {
  const HoldToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.holdDuration = const Duration(milliseconds: 900),
  });

  final String label;
  final VoidCallback onConfirmed;

  /// How long the finger must stay down.
  final Duration holdDuration;

  @override
  State<HoldToConfirm> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.holdDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _confirm();
        });
  bool _done = false;

  void _confirm() {
    if (_done) return;
    _done = true;
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
  }

  void _press() {
    if (_done) return;
    HapticFeedback.selectionClick();
    _c.forward();
  }

  void _release() {
    if (_done) return;
    // Drain faster than it filled.
    _c.animateBack(
      0,
      duration: DaftarMotion.base,
      curve: DaftarMotion.standard,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: widget.label,
      onLongPress: _confirm,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Container(
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: Radii.buttonR,
              border: Border.all(color: c.coral),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _c.value,
                    child: ColoredBox(color: c.coral.withValues(alpha: 0.25)),
                  ),
                ),
                Center(
                  child: Text(
                    widget.label,
                    style: t.labelLarge?.copyWith(
                      color: c.coral,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks the user to hold a button before something is hidden or deleted. Returns
/// true only when the hold completed.
Future<bool> showHoldToConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String label = 'Hold to confirm',
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: t.headlineSmall),
                const SizedBox(height: Space.sm),
                Text(message, style: t.bodyMedium),
                const SizedBox(height: Space.xl),
                HoldToConfirm(
                  label: label,
                  onConfirmed: () => Navigator.of(sheetContext).pop(true),
                ),
                const SizedBox(height: Space.sm),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(Chrome.minTouch),
                  ),
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}
