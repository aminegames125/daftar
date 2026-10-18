import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/core/theme/app_theme.dart';
import '../ui/core/widgets/glass_config.dart';
import '../ui/core/widgets/theme_reveal.dart';
import '../ui/features/lock/views/lock_gate.dart';
import 'router.dart';
import 'settings.dart';
import 'share_listener.dart';

class DaftarApp extends ConsumerWidget {
  const DaftarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Daftar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      // Outside in: theme reveal → app lock → glass setting → the router.
      builder: (context, child) => ThemeRevealHost(
        controller: ref.watch(themeRevealProvider),
        child: LockGate(
          child: ShareListener(
            child: GlassConfig(
              blur: ref.watch(glassBlurProvider),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
