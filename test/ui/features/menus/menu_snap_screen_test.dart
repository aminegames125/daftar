import 'dart:io';

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/places_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/ocr_service.dart';
import 'package:daftar/data/services/photo_store.dart';
import 'package:daftar/domain/menu_logic/menu_line_parser.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/menus/views/menu_snap_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class _Store implements PhotoStore {
  @override
  Future<String?> pick(ImageSource source, {double maxWidth = 1600}) async =>
      'photos/menu.jpg';
  @override
  Future<String> import(String sourcePath) async => sourcePath;
  @override
  Future<File> resolve(String storedPath) async => File(storedPath);
  @override
  Future<void> deleteFile(String storedPath) async {}
}

class _Ocr implements OcrService {
  _Ocr(this.lines);
  final List<String> lines;

  @override
  Future<OcrResult> recognize(String imagePath) async => OcrResult(
    text: lines.join('\n'),
    lines: [for (final l in lines) OcrLine(l, confidence: 0.95)],
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pump(
    WidgetTester tester,
    List<String> ocrLines, {
    String? placeId = 'p1',
    bool dark = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => DriftPlacesRepository(db).save(
        Place(
          id: 'p1',
          name: 'Café Yasmine',
          typeId: builtInId('place_type', 'cafe'),
        ),
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MenuSnapScreen(placeId: placeId),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          photoStoreProvider.overrideWithValue(_Store()),
          ocrServiceProvider.overrideWithValue(_Ocr(ocrLines)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  // Drift schedules zero-length timers when a stream loses its last listener.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> snapPhoto(WidgetTester tester) async {
    await tester.tap(find.text('Take a photo'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('scan, fix a typo, save: menu and prices are stored', (
    tester,
  ) async {
    await pump(tester, ['Boissons', 'Express 1,8', 'Capucin S 3.2 L 4.0']);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Type it myself'), findsOneWidget);

    await snapPhoto(tester);
    expect(
      find.text(
        "This one's hard to read. Typing it yourself will be more accurate.",
      ),
      findsNothing,
    );
    expect(find.text('Check the menu'), findsWidgets);
    expect(find.text('Save 2 items'), findsWidgets);
    expect(find.text('Boissons'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Express'),
      'Espresso',
    );
    await tester.pump(
      const Duration(seconds: 2),
    ); // let the toolbar spring settle
    await tester.tap(find.bySemanticsLabel('Save 2 items'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1500)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1000));

    final items = (await tester.runAsync(() => db.select(db.menuItems).get()))!;
    expect(items.map((i) => i.name), ['Espresso', 'Capucin']);
    final prices = (await tester.runAsync(
      () => db.select(db.priceEntries).get(),
    ))!;
    expect(
      prices.map((p) => p.amountMinor)..toList(),
      unorderedEquals([1800, 3200, 4000]),
    );
    final photos = (await tester.runAsync(() => db.select(db.photos).get()))!;
    expect(photos.single.filePath, 'photos/menu.jpg');
    expect(photos.single.ocrText, contains('Capucin'));
    await tester.pump(const Duration(seconds: 4));
    await unmount(tester);
  });

  testWidgets('Arabic / unreliable scans show the hard-to-read hint', (
    tester,
  ) async {
    await pump(tester, ['قهوة 2,5', 'شاي 1,5'], dark: false);
    await snapPhoto(tester);
    expect(
      find.text(
        "This one's hard to read. Typing it yourself will be more accurate.",
      ),
      findsOneWidget,
    );
    expect(find.text('Retake photo'), findsOneWidget);
    expect(find.text('Type it myself'), findsOneWidget);

    // "Type it myself" drops the scan and offers an empty row.
    await tester.tap(find.text('Type it myself'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(
        "This one's hard to read. Typing it yourself will be more accurate.",
      ),
      findsNothing,
    );
    await unmount(tester);
  });

  testWidgets('typing a menu by hand', (tester) async {
    await pump(tester, const []);
    await tester.tap(find.text('Type it myself'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Check the menu'), findsWidgets);
    expect(find.text('Add item'), findsOneWidget);
    expect(find.text('Add a section'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('without ?placeId= it asks which place first', (tester) async {
    await pump(tester, const [], placeId: null);
    expect(find.text('Which place is it from?'), findsOneWidget);
    expect(find.text('Café Yasmine'), findsOneWidget);
    await tester.tap(find.text('Café Yasmine'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Take a photo'), findsOneWidget);
    await unmount(tester);
  });
}
