import 'package:flutter/material.dart';

import '../brand/dal_mark.dart';
import '../motion/daftar_motion.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';

/// Motion empty state: a muted Dal drifting gently above one sentence and
/// (optionally) one action. Centered; wrap it in `Center`/`SliverFillRemaining`
/// yourself if the parent is not already bounded.
///
/// ```dart
/// EmptyState(
///   message: 'No places yet. Add the first one.',
///   actionLabel: 'Add place',
///   onAction: () => context.push(Routes.placeNew),
/// )
/// ```
class EmptyState extends StatefulWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.markSize = 72,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double markSize;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 3200);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _period,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = DaftarMotion.reduced(context);
    if (reduced) {
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
    final t = Theme.of(context).textTheme;
    const drift = Space.sm;
    // Scrolls rather than overflows when text is huge and the box is short.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  0,
                  -drift * DaftarMotion.emphasized.transform(_c.value),
                ),
                child: child,
              ),
              child: ExcludeSemantics(
                child: DalMark(size: widget.markSize, color: c.line),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              widget.message,
              style: t.bodyMedium?.copyWith(color: c.muted),
              textAlign: TextAlign.center,
            ),
            if (widget.actionLabel != null) ...[
              const SizedBox(height: Space.lg),
              FilledButton.tonal(
                onPressed: widget.onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: c.raised,
                  foregroundColor: c.text,
                  minimumSize: const Size(64, Chrome.minTouch),
                ),
                child: Text(widget.actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
