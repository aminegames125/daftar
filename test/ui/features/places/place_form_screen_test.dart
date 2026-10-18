import 'dart:io';

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/geocoding_location.dart';
import 'package:daftar/data/services/photo_store.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/places/views/place_form_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class _FakeStore implements PhotoStore {
  @override
  Future<String?> pick(ImageSource source, {double maxWidth = 1600}) async =>
      null;
  @override
  Future<String> import(String sourcePath) async => sourcePath;
  @override
  Future<File> resolve(String storedPath) async => File(storedPath);
  @override
  Future<void> deleteFile(String storedPath) async {}
}

class _DeniedLocation implements LocationService {
  @override
  Future<LocationFix> currentPosition() async =>
      const LocationFix.failure(LocationStatus.permissionDenied);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // Drift schedules zero-length timers when a stream loses its last listener;
  // unmount the tree and let them run before the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> pumpForm(
    WidgetTester tester, {
    String? placeId,
    bool dark = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PlaceFormScreen(placeId: placeId),
        ),
        GoRoute(
          path: '/settings/lists/:kind',
          builder: (_, state) =>
              Scaffold(body: Text('manage ${state.pathParameters['kind']}')),
        ),
        GoRoute(
          path: '/places/:id',
          builder: (_, state) =>
              Scaffold(body: Text('detail ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          photoStoreProvider.overrideWithValue(_FakeStore()),
          locationServiceProvider.overrideWithValue(_DeniedLocation()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
    );
    // Let the form load its types from the in-memory database.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('type and payment sections link to list management', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.tap(find.text('Manage').first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('manage placeTypes'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('shows every section of the place form', (tester) async {
    await pumpForm(tester);
    for (final text in [
      'Add place',
      'Type',
      'Location',
      'Opening hours',
      'Wi-Fi',
      'Payment methods',
      'Your rating',
      'Quick tags',
      'Notes',
      'Photos',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.text('Supermarket'), findsOneWidget);
    expect(find.text('Café'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Clean'), findsOneWidget);
    expect(find.text("I'm here"), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a place needs a name; then it is saved and its page opens', (
    tester,
  ) async {
    await pumpForm(tester);

    await tester.tap(find.bySemanticsLabel('Add place').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Give the place a name'), findsOneWidget);
    expect(await tester.runAsync(() => db.select(db.places).get()), isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Café Yasmine',
    );
    await tester.tap(find.text('Café'));
    await tester.tap(find.text('Cash'));
    await tester.tap(find.text('Clean'));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Add place').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final rows = (await tester.runAsync(() => db.select(db.places).get()))!;
    expect(rows.single.name, 'Café Yasmine');
    expect(find.textContaining('detail '), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // toast
    await unmount(tester);
  });

  testWidgets(
    '"I\'m here" without permission explains and keeps the form usable',
    (tester) async {
      await pumpForm(tester, dark: false);
      await tester.tap(find.text("I'm here"));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('permission was denied'), findsOneWidget);
      expect(find.text('Pick on map'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('hours switch reveals the weekly editor', (tester) async {
    await pumpForm(tester);
    expect(find.text('Mon'), findsNothing);
    await tester.tap(find.text('Set the weekly hours'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);
    await unmount(tester);
  });
}
