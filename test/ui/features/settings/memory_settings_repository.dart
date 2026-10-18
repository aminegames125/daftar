import 'package:daftar/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart' show ThemeMode;

/// In-memory [SettingsRepository] for widget tests (no database, no real async).
class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([Map<String, String>? initial])
    : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Stream<String?> watch(String key) => Stream.value(values[key]);

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<ThemeMode> getThemeMode() async =>
      ThemeMode.values.asNameMap()[values[SettingKeys.themeMode]] ??
      ThemeMode.dark;

  @override
  Future<void> setThemeMode(ThemeMode mode) =>
      set(SettingKeys.themeMode, mode.name);

  @override
  Future<int> getStaleDays() async =>
      int.tryParse(values[SettingKeys.staleDays] ?? '') ?? 90;

  @override
  Future<void> setStaleDays(int days) => set(SettingKeys.staleDays, '$days');
}
