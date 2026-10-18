import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../motion/daftar_motion.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';
import 'glass_surface.dart';

enum ToastKind { info, success, error }

/// Motion floating toast: a glass pill drops in from the top with a spring,
/// waits, then slips away. One toast at a time: a new one replaces the old.
///
/// ```dart
/// FloatingToast.show(context, 'Price saved', subtitle: 'Milka Oreo · 4.400 TND',
///     kind: ToastKind.success);
/// ```
abstract final class FloatingToast {
  /// How long a toast stays before it leaves on its own.
  static const Duration displayTime = Duration(milliseconds: 2600);

  static _ToastHandle? _current;

  static void show(
    BuildContext context,
    String message, {
    String? subtitle,
    ToastKind kind = ToastKind.info,
    Duration duration = displayTime,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _current?.dismissNow();

    final reduced = DaftarMotion.reduced(context);
    late final OverlayEntry entry;
    final handle = _ToastHandle();
    entry = OverlayEntry(
      builder: (context) => _ToastView(
        handle: handle,
        message: message,
        subtitle: subtitle,
        kind: kind,
        duration: duration,
        reduced: reduced,
        actionLabel: actionLabel,
        onAction: onAction,
        onGone: () {
          if (entry.mounted) entry.remove();
          entry.dispose();
          if (identical(_current, handle)) _current = null;
        },
      ),
    );
    _current = handle;
    overlay.insert(entry);
    if (kind == ToastKind.error) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Removes the current toast, if any.
  static void dismiss() => _current?.dismiss();
}

class _ToastHandle {
  VoidCallback? _dismiss;
  VoidCallback? _dismissNow;

  void dismiss() => _dismiss?.call();
  void dismissNow() => _dismissNow?.call();
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.handle,
    required this.message,
    required this.subtitle,
    required this.kind,
    required this.duration,
    required this.reduced,
    required this.actionLabel,
    required this.onAction,
    required this.onGone,
  });

  final _ToastHandle handle;
  final String message;
  final String? subtitle;
  final ToastKind kind;
  final Duration duration;
  final bool reduced;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onGone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _v = AnimationController.unbounded(
    vsync: this,
    value: widget.reduced ? 1 : 0,
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.handle._dismiss = _leave;
    widget.handle._dismissNow = _goneNow;
    if (!widget.reduced) {
      _v.animateWith(SpringSimulation(DaftarMotion.bouncy, 0, 1, 0));
    }
    _timer = Timer(widget.duration, _leave);
  }

  void _goneNow() {
    _timer?.cancel();
    widget.onGone();
  }

  void _leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    if (widget.reduced) {
      widget.onGone();
      return;
    }
    _v
        .animateWith(
          SpringSimulation(DaftarMotion.effects, _v.value, 0, _v.velocity),
        )
        .whenComplete(() {
          if (mounted) widget.onGone();
        });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final top = MediaQuery.paddingOf(context).top + Space.md;
    final (Color badge, Color onBadge, IconData icon) = switch (widget.kind) {
      ToastKind.success => (c.lime, c.onLime, Icons.check_rounded),
      ToastKind.error => (c.coral, c.onLime, Icons.close_rounded),
      ToastKind.info => (c.raised, c.text, Icons.info_outline_rounded),
    };

    return Positioned(
      top: top,
      left: Space.lg,
      right: Space.lg,
      child: AnimatedBuilder(
        animation: _v,
        builder: (context, child) => Opacity(
          opacity: _v.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (_v.value - 1) * (top + Chrome.barHeight)),
            child: child,
          ),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Semantics(
            liveRegion: true,
            label: widget.subtitle == null
                ? widget.message
                : '${widget.message}. ${widget.subtitle}',
            child: GestureDetector(
              onTap: _leave,
              child: Material(
                type: MaterialType.transparency,
                child: GlassSurface(
                  padding: const EdgeInsets.fromLTRB(
                    Space.md,
                    Space.sm,
                    Space.lg,
                    Space.sm,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: Chrome.minTouch,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: badge,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, size: 18, color: onBadge),
                        ),
                        const SizedBox(width: Space.md),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.message,
                                style: t.labelLarge,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.subtitle != null)
                                Text(
                                  widget.subtitle!,
                                  style: t.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (widget.actionLabel != null) ...[
                          const SizedBox(width: Space.md),
                          TextButton(
                            onPressed: () {
                              widget.onAction?.call();
                              _leave();
                            },
                            child: Text(
                              widget.actionLabel!,
                              style: t.labelLarge?.copyWith(
                                color: c.accentText,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
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
