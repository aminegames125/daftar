import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/settings.dart';
import 'data/data_providers.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/database/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Phone app: portrait only (landscape cut the wallet and floating nav).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Open the database (creating + seeding it on first launch) and read the saved
  // theme so the first frame already uses it.
  final db = AppDatabase();
  final themeMode = await DriftSettingsRepository(db).getThemeMode();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialThemeModeProvider.overrideWithValue(themeMode),
      ],
      child: const DaftarApp(),
    ),
  );
}
