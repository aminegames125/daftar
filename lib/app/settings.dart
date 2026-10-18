import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_providers.dart';
import '../data/repositories/settings_repository.dart';
import '../domain/models/product.dart';

/// Theme mode read from the database before the first frame. `main()` overrides
/// it; dark is the default (brand decision D3).
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.dark);

/// App theme mode, saved in the `settings` table.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> set(ThemeMode mode) {
    state = mode;
    return ref.read(settingsRepositoryProvider).setThemeMode(mode);
  }
}

/// Extra `settings` keys owned by the app shell (the repository's [SettingKeys]
/// file is frozen, so they live here).
abstract final class AppSettingKeys {
  /// 'true' / 'false'. Frosted blur on floating glass (turn off on slow phones).
  static const glassBlur = 'glass_blur';

  /// Comma-separated `HomeCardId` names, front card first.
  static const homeCardOrder = 'home_card_order';
}

/// Whether floating glass surfaces blur what is behind them. Defaults to on and
/// loads the saved value right after start-up (a one-frame difference at most).
final glassBlurProvider = NotifierProvider<GlassBlurController, bool>(
  GlassBlurController.new,
);

class GlassBlurController extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    try {
      final saved = await ref
          .read(settingsRepositoryProvider)
          .get(AppSettingKeys.glassBlur);
      if (saved != null && ref.mounted) state = saved == 'true';
    } catch (_) {
      // No database (e.g. a bare widget test): keep the default.
    }
  }

  Future<void> set(bool value) {
    state = value;
    return ref
        .read(settingsRepositoryProvider)
        .set(AppSettingKeys.glassBlur, '$value');
  }
}

/// Days after which a price counts as "old" (decision D15, default 90). Saved in
/// the `settings` table. Starts at the default and updates once the saved value
/// has loaded; `staleDaysProvider.notifier.set(…)` saves.
final staleDaysProvider = NotifierProvider<StaleDaysController, int>(
  StaleDaysController.new,
);

class StaleDaysController extends Notifier<int> {
  static const int min = 7;
  static const int max = 730;

  @override
  int build() {
    _load();
    return DriftSettingsRepository.defaultStaleDays;
  }

  Future<void> _load() async {
    try {
      final days = await ref.read(settingsRepositoryProvider).getStaleDays();
      if (ref.mounted) state = days;
    } catch (_) {
      // No database (bare widget test): keep the default.
    }
  }

  Future<void> set(int days) {
    state = days.clamp(min, max);
    return ref.read(settingsRepositoryProvider).setStaleDays(state);
  }
}

/// Unit pre-selected when logging a size (decision D13 keeps size optional).
/// null = no default. Saved under [SettingKeys.defaultUnit].
final defaultUnitProvider = NotifierProvider<DefaultUnitController, SizeUnit?>(
  DefaultUnitController.new,
);

class DefaultUnitController extends Notifier<SizeUnit?> {
  @override
  SizeUnit? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final saved = await ref
          .read(settingsRepositoryProvider)
          .get(SettingKeys.defaultUnit);
      if (ref.mounted) state = SizeUnit.values.asNameMap()[saved];
    } catch (_) {
      // No database: no default unit.
    }
  }

  Future<void> set(SizeUnit? unit) {
    state = unit;
    return ref
        .read(settingsRepositoryProvider)
        .set(SettingKeys.defaultUnit, unit?.name ?? '');
  }
}
