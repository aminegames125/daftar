import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../services/database/app_database.dart';

/// Keys of the `settings` table (DATA_MODEL § 2).
abstract final class SettingKeys {
  static const themeMode = 'theme_mode';
  static const staleDays = 'stale_days';
  static const defaultUnit = 'default_unit';
  static const lockEnabled = 'lock_enabled';
}

abstract interface class SettingsRepository {
  Future<String?> get(String key);
  Stream<String?> watch(String key);
  Future<void> set(String key, String value);

  /// Dark is the default (brand decision D3).
  Future<ThemeMode> getThemeMode();
  Future<void> setThemeMode(ThemeMode mode);

  /// Days after which a price is "old" (D15). Defaults to 90.
  Future<int> getStaleDays();
  Future<void> setStaleDays(int days);
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  static const defaultStaleDays = 90;

  SimpleSelectStatement<$SettingsTable, Setting> _row(String key) =>
      _db.select(_db.settings)..where((s) => s.key.equals(key));

  @override
  Future<String?> get(String key) async =>
      (await _row(key).getSingleOrNull())?.value;

  @override
  Stream<String?> watch(String key) =>
      _row(key).watchSingleOrNull().map((row) => row?.value);

  @override
  Future<void> set(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  @override
  Future<ThemeMode> getThemeMode() async {
    final name = await get(SettingKeys.themeMode);
    return ThemeMode.values.asNameMap()[name] ?? ThemeMode.dark;
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) =>
      set(SettingKeys.themeMode, mode.name);

  @override
  Future<int> getStaleDays() async =>
      int.tryParse(await get(SettingKeys.staleDays) ?? '') ?? defaultStaleDays;

  @override
  Future<void> setStaleDays(int days) => set(SettingKeys.staleDays, '$days');
}
