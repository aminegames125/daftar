import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/shake.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../view_models/lock_controller.dart';

/// Motion PIN entry: dots fill as you type; a wrong PIN turns the dots coral
/// and shakes them. Shows the keypad below.
///
/// [onSubmit] gets the full PIN and returns an error message to show (the PIN is
/// cleared), or null when it was accepted.
class PinEntry extends StatefulWidget {
  const PinEntry({
    super.key,
    required this.title,
    required this.onSubmit,
    this.hint,
    this.leftKey,
    this.length = pinLength,
  });

  final String title;
  final String? hint;
  final int length;
  final Future<String?> Function(String pin) onSubmit;

  /// The key at the bottom left (the fingerprint button on the lock screen).
  final Widget? leftKey;

  @override
  State<PinEntry> createState() => PinEntryState();
}

class PinEntryState extends State<PinEntry> {
  String _digits = '';
  String? _error;
  int _errors = 0;
  bool _busy = false;

  /// Shows [message] as an error and clears the dots (also used by the lock screen
  /// when the fingerprint fails).
  void showError(String message) {
    HapticFeedback.mediumImpact();
    setState(() {
      _error = message;
      _errors++;
      _digits = '';
    });
  }

  Future<void> _add(String digit) async {
    if (_busy || _digits.length >= widget.length) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _digits += digit;
      _error = null;
    });
    if (_digits.length == widget.length) {
      _busy = true;
      final pin = _digits;
      final error = await widget.onSubmit(pin);
      _busy = false;
      if (!mounted) return;
      if (error != null) showError(error);
    }
  }

  void _back() {
    if (_busy || _digits.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final hasError = _error != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: t.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: 20,
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error ?? widget.hint ?? '',
              style: t.bodySmall?.copyWith(color: hasError ? c.coral : c.muted),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: Space.xl),
        Shake(
          trigger: _errors,
          child: Semantics(
            label: '${_digits.length} of ${widget.length} digits entered',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    child: _Dot(filled: i < _digits.length, error: hasError),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.xxxl),
        PinPad(onDigit: _add, onBackspace: _back, leftKey: widget.leftKey),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.filled, required this.error});

  final bool filled;
  final bool error;

  static const double size = 16;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = error ? c.coral : c.accentText;
    final reduced = DaftarMotion.reduced(context);
    return AnimatedContainer(
      duration: reduced ? Duration.zero : DaftarMotion.fast,
      curve: DaftarMotion.pop,
      width: size,
      height: size,
      transform: Matrix4.diagonal3Values(
        filled ? 1.0 : 0.85,
        filled ? 1.0 : 0.85,
        1,
      ),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(
          color: filled ? color : (error ? c.coral : c.line),
          width: 2,
        ),
      ),
    );
  }
}

/// 3 × 4 numeric keypad.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.leftKey,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget? leftKey;

  static const double keySize = 72;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> keys) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: keys),
    );
    Widget digit(String d) =>
        PadKey(label: d, semanticsLabel: d, onTap: () => onDigit(d));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        row([digit('4'), digit('5'), digit('6')]),
        row([digit('7'), digit('8'), digit('9')]),
        row([
          leftKey ?? const SizedBox(width: keySize + Space.lg, height: keySize),
          digit('0'),
          PadKey(
            icon: Icons.backspace_outlined,
            semanticsLabel: 'Delete',
            onTap: onBackspace,
          ),
        ]),
      ],
    );
  }
}

/// One round key of the keypad.
class PadKey extends StatelessWidget {
  const PadKey({
    super.key,
    this.label,
    this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Semantics(
        button: true,
        label: semanticsLabel,
        excludeSemantics: true,
        onTap: onTap,
        child: Squish(
          onTap: onTap,
          pressedScale: 0.92,
          child: Container(
            width: PinPad.keySize,
            height: PinPad.keySize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: label == null ? Colors.transparent : c.raised,
              shape: BoxShape.circle,
            ),
            child: label != null
                ? Text(label!, style: DaftarType.price(28, c.text))
                : Icon(icon, color: c.muted, size: 24),
          ),
        ),
      ),
    );
  }
}
