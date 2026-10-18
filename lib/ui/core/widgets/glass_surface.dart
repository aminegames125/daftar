import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';
import 'glass_config.dart';

/// Frosted glass for FLOATING surfaces only: nav pill, action toolbar, toasts,
/// FAB menu items. Never use it on forms, lists or tables
/// Glass).
///
/// [blur] can be turned off for low-end devices; the fill stays
/// semi-opaque so text keeps its contrast either way.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = Radii.pillR,
    this.blur,
    this.padding,
    this.height,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// null = follow the app-wide setting ([GlassConfig], default on).
  final bool? blur;
  final EdgeInsetsGeometry? padding;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final blur = this.blur ?? GlassConfig.blurOf(context);
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget body = Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: blur ? c.glass : c.glass.withValues(alpha: 0.96),
        borderRadius: borderRadius,
        border: Border.all(color: c.glassBorder),
      ),
      child: child,
    );

    if (blur) {
      body = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: body,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.14),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: body,
    );
  }
}
