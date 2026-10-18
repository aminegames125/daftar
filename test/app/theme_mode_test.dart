import 'package:daftar/app/settings.dart';
import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/settings_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer container([ThemeMode initial = ThemeMode.dark]) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialThemeModeProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts from the saved theme mode', () {
    expect(container(ThemeMode.light).read(themeModeProvider), ThemeMode.light);
  });

  test(
    'changing the theme updates state and is saved in the settings table',
    () async {
      final c = container();
      expect(c.read(themeModeProvider), ThemeMode.dark);

      await c.read(themeModeProvider.notifier).set(ThemeMode.light);

      expect(c.read(themeModeProvider), ThemeMode.light);
      expect(await DriftSettingsRepository(db).getThemeMode(), ThemeMode.light);
    },
  );
}
