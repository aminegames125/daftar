import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';

/// Wraps [child] in the Daftar theme (dark by default) for widget tests.
Widget testApp(
  Widget child, {
  bool dark = true,
  bool reduceMotion = false,
  double textScale = 1,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: w!,
      ),
      home: Scaffold(extendBody: true, body: child),
    ),
  );
}

/// Like [testApp] but with a [GoRouter] (for screens that navigate).
Widget testRouterApp(
  GoRouter router, {
  bool dark = true,
  bool reduceMotion = true,
  double textScale = 1,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    key: UniqueKey(), // a fresh container (and notifiers) for every pump
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: w!,
      ),
    ),
  );
}

/// Like [testApp] but [scaffold] is the whole screen (so it can own its
/// bottom bars, the way the router's screens do).
Widget testAppScaffold({
  required Widget scaffold,
  double textScale = 1,
  bool dark = true,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: w!,
      ),
      home: scaffold,
    ),
  );
}
