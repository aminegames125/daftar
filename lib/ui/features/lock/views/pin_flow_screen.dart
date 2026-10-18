import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../view_models/lock_controller.dart';
import 'pin_entry.dart';

enum PinFlowMode {
  /// Choose a new PIN (twice). Pops with the PIN.
  create,

  /// Check the current PIN. Pops with the PIN.
  verify,
}

/// Full-screen PIN prompt used by Settings to turn the lock on (create), and to
/// confirm the current PIN before changing or turning it off (verify). Pops with the
/// entered PIN, or null when the user goes back.
class PinFlowScreen extends ConsumerStatefulWidget {
  const PinFlowScreen({super.key, required this.mode});

  final PinFlowMode mode;

  @override
  ConsumerState<PinFlowScreen> createState() => _PinFlowScreenState();
}

class _PinFlowScreenState extends ConsumerState<PinFlowScreen> {
  String? _first;
  Key _entryKey = UniqueKey();

  Future<String?> _submit(String pin) async {
    switch (widget.mode) {
      case PinFlowMode.verify:
        final result = await ref
            .read(lockControllerProvider.notifier)
            .checkPin(pin);
        if (!mounted) return null;
        return switch (result) {
          PinCheck.ok => _done(pin),
          PinCheck.wrong => 'Wrong PIN',
          PinCheck.blocked =>
            'Too many tries. Wait ${ref.read(lockControllerProvider.notifier).blockedSeconds()} s',
        };
      case PinFlowMode.create:
        final first = _first;
        if (first == null) {
          setState(() {
            _first = pin;
            _entryKey = UniqueKey();
          });
          return null;
        }
        if (first != pin) {
          // Same entry widget, so it can show the message; it clears its dots itself.
          setState(() => _first = null);
          return 'The PINs did not match. Try again';
        }
        return _done(pin);
    }
  }

  String? _done(String pin) {
    context.pop(pin);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final creating = widget.mode == PinFlowMode.create;
    final title = !creating
        ? 'Enter your PIN'
        : _first == null
        ? 'Choose a PIN'
        : 'Repeat your PIN';
    final hint = !creating
        ? null
        : _first == null
        ? '$pinLength digits you will remember'
        : 'Type it once more to confirm';

    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: creating ? 'Set a PIN' : 'Confirm it\'s you',
            expandedHeight: 96,
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: () => context.pop(),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                // The entry is rebuilt (cleared) between the two steps of "create".
                child: PinEntry(
                  key: _entryKey,
                  title: title,
                  hint: hint,
                  onSubmit: _submit,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
