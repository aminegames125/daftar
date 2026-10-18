import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/dal_mark.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/lock_controller.dart';
import 'fingerprint_button.dart';
import 'pin_entry.dart';

/// Full-screen lock: a breathing Dal, PIN dots and keypad and an
/// optional fingerprint key.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final GlobalKey<PinEntryState> _pin = GlobalKey();
  bool _biometricAvailable = false;
  bool _scanning = false;
  bool _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkBiometric());
  }

  Future<void> _checkBiometric() async {
    final controller = ref.read(lockControllerProvider.notifier);
    final available = await controller.biometricAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    // Offer the fingerprint right away, once per time the lock screen shows.
    if (available &&
        ref.read(lockControllerProvider).biometric &&
        !_autoPrompted) {
      _autoPrompted = true;
      await _scan();
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    await ref.read(lockControllerProvider.notifier).unlockWithBiometric();
    if (!mounted) return;
    // Cancelled or not recognised: the PIN pad is right there, no scolding.
    setState(() => _scanning = false);
  }

  Future<String?> _submit(String pin) async {
    final controller = ref.read(lockControllerProvider.notifier);
    return switch (await controller.unlockWithPin(pin)) {
      PinCheck.ok => null,
      PinCheck.wrong => 'Wrong PIN',
      PinCheck.blocked =>
        'Too many tries. Wait ${controller.blockedSeconds()} s',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showFingerprint =
        _biometricAvailable &&
        ref.watch(lockControllerProvider.select((s) => s.biometric));

    return Material(
      color: c.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BreathingDal(size: 72),
                      const SizedBox(height: Space.xxxl),
                      PinEntry(
                        key: _pin,
                        title: 'Enter your PIN',
                        hint: 'Daftar is locked',
                        onSubmit: _submit,
                        leftKey: showFingerprint
                            ? FingerprintKey(scanning: _scanning, onTap: _scan)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Motion breathe: the Dal swells a few percent with a soft lime glow. A still
/// mark with "Remove animations" on.
class BreathingDal extends StatefulWidget {
  const BreathingDal({super.key, this.size = 72});

  final double size;

  @override
  State<BreathingDal> createState() => _BreathingDalState();
}

class _BreathingDalState extends State<BreathingDal>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 3200);
  static const double _swell = 0.04;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _period,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DaftarMotion.reduced(context)) {
      _c.stop();
      _started = false;
    } else if (!_started) {
      _started = true;
      _c.repeat(reverse: true);
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = DaftarMotion.emphasized.transform(_c.value);
        return Transform.scale(
          scale: 1 + _swell * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.lime.withValues(alpha: 0.10 + 0.18 * t),
                  blurRadius: widget.size * (0.5 + 0.4 * t),
                ),
              ],
            ),
            child: DalMark(size: widget.size),
          ),
        );
      },
    );
  }
}
