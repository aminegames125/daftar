import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/dal_mark.dart';
import '../../../core/theme/daftar_colors.dart';
import '../view_models/lock_controller.dart';
import 'lock_screen.dart';

/// Covers the app with the lock screen while it is locked, and re-locks it when the
/// user has been away longer than their chosen delay. Sits above the router
/// (`MaterialApp.builder`).
///
/// Until the saved settings are read, the app stays covered by a plain Dal so that
/// private content never flashes before the lock appears.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        lock.onBackgrounded();
      case AppLifecycleState.resumed:
        lock.onResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(lockControllerProvider);
    final covered = !lock.ready || lock.locked;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(
          excluding: covered,
          child: TickerMode(
            enabled: !covered,
            child: IgnorePointer(ignoring: covered, child: widget.child),
          ),
        ),
        if (!lock.ready)
          Positioned.fill(
            child: ColoredBox(
              color: context.colors.background,
              child: const Center(child: DalMark(size: 72)),
            ),
          )
        else if (lock.locked)
          const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}
