import 'dart:async';

import 'dart:typed_data';

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/places_repository.dart';
import 'package:daftar/data/repositories/products_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/open_food_facts_provider.dart';
import 'package:daftar/data/services/open_food_facts_service.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/core/widgets/money_field.dart';
import 'package:daftar/ui/features/prices/view_models/photo_store.dart';
import 'package:daftar/ui/features/prices/view_models/user_location.dart';
import 'package:daftar/ui/features/prices/views/log_price_screen.dart';
import 'package:daftar/ui/features/prices/views/widgets/form_bits.dart';
import 'package:daftar/ui/features/products/view_models/catalog_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final fixedNow = DateTime(2026, 10, 16, 12);

final _sizeField = find.byType(TextField).at(1);
final _priceField = find
    .descendant(of: find.byType(MoneyField), matching: find.byType(TextField))
    .first;

class _NoNetwork implements OpenFoodFactsService {
  @override
  Future<OffResult> lookup(String barcode) async =>
      const OffUnavailable('test');

  @override
  Future<Uint8List?> downloadImage(String url) async => null;
}

class _FakePhotos implements PhotoStore {
  @override
  Future<String> importFile(String sourcePath) async => '/photos/x.jpg';

  @override
  Future<String> saveBytes(Uint8List bytes) async => '/photos/y.jpg';
}

void main() {
  late AppDatabase db;

  setUp(
    () => db = AppDatabase(NativeDatabase.memory(), () => fixedNow.toUtc()),
  );

  /// Like testWidgets, but closes the database on real time: drift's stream
  /// cleanup needs real timers, so closing inside the fake-async zone would hang.
  void screenTest(
    String name,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(name, (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        // Let drift's deferred stream clean-up timers fire before closing.
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await db.close();
        });
      }
    });
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    ThemeData? theme,
    bool reduced = true,
  }) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (_, _) => const Scaffold(body: Text('START')),
        ),
        GoRoute(path: '/prices/new', builder: (_, _) => const LogPriceScreen()),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/scan',
          builder: (_, _) => const Scaffold(body: Text('SCAN')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => fixedNow),
          userLocationProvider.overrideWith((ref) async => null),
          openFoodFactsServiceProvider.overrideWithValue(_NoNetwork()),
          photoStoreProvider.overrideWithValue(_FakePhotos()),
        ],
        child: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduced,
            size: const Size(390, 2600),
          ),
          child: MaterialApp.router(
            routerConfig: router,
            theme: theme ?? AppTheme.dark(),
          ),
        ),
      ),
    );
    unawaited(router.push<void>('/prices/new'));
    await _settle(tester);
  }

  screenTest('shows every field of the brand screen', (tester) async {
    await pumpScreen(tester);

    for (final text in [
      'Log a price',
      'Product',
      'Size',
      'Price',
      'Where',
      'Promo',
      'I bought it',
      'Pick the account after saving',
      'Save price',
      'Global',
      'Range',
      'Note',
    ]) {
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
    expect(find.text('TND'), findsOneWidget);
    expect(find.bySemanticsLabel('Scan barcode'), findsOneWidget);
    for (final unit in ['g', 'kg', 'ml', 'L', 'pc']) {
      expect(find.bySemanticsLabel(unit), findsOneWidget, reason: unit);
    }
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
  });

  screenTest('"I bought it" can be switched on', (tester) async {
    await pumpScreen(tester);
    final toggle = find.byType(DaftarSwitch).last;
    expect(tester.widget<DaftarSwitch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await _settle(tester);
    expect(tester.widget<DaftarSwitch>(toggle).value, isTrue);
  });

  screenTest('shows the live unit price while typing size and price', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(_sizeField, '100');
    await tester.enterText(_priceField, '4,4');
    await _settle(tester);

    expect(find.text('= 44.000 TND / kg'), findsOneWidget);
  });

  screenTest('the range toggle adds a highest price', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Highest price'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Min–max range'));
    await _settle(tester);
    expect(find.text('Highest price'), findsOneWidget);
    expect(find.text('Lowest price'), findsOneWidget);
  });

  screenTest('Global shows the type labels', (tester) async {
    await pumpScreen(tester);

    await tester.tap(
      find.bySemanticsLabel('Global price, not tied to a store'),
    );
    await _settle(tester);
    expect(find.text('Reference price'), findsOneWidget);
    expect(find.text('Seen somewhere'), findsOneWidget);
    expect(find.text('Official price'), findsOneWidget);
    expect(find.text('+ Type'), findsOneWidget);
  });

  screenTest('promo shows an end-date row', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.bySemanticsLabel('Promo'));
    await _settle(tester);
    expect(find.text('Ends'), findsOneWidget);
    expect(find.text('No end date'), findsOneWidget);
  });

  screenTest('saving an empty form shows what is missing and stays', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Save price'));
    await _settle(tester);

    expect(find.text('What did you see? Type a product.'), findsOneWidget);
    expect(find.text('Enter the price.'), findsOneWidget);
    expect(find.text('Pick the place, or choose Global.'), findsOneWidget);
    expect(find.text('Log a price'), findsOneWidget);
  });

  screenTest('suggests existing products and offers their variants', (
    tester,
  ) async {
    await _runAsync(tester, () => _seedMilka(db));
    await pumpScreen(tester);

    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'mil');
    await _settle(tester);

    expect(find.text('Milka'), findsWidgets);
    expect(find.text('New product “mil”'), findsOneWidget);

    await tester.tap(find.text('Mondelez'));
    await _settle(tester);

    expect(find.text('Oreo · 100 g'), findsOneWidget);
    expect(find.text('Noisette'), findsOneWidget);
    expect(find.text('+ Variant'), findsOneWidget);
    // The first variant's size is pre-filled.
    expect(tester.widget<TextField>(_sizeField).controller!.text, '100');
  });

  screenTest('a full entry is saved and the success check appears', (
    tester,
  ) async {
    await _runAsync(tester, () async {
      await _seedMilka(db);
      await _seedPlace(db);
    });
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'Water');
    await tester.enterText(_priceField, '1.250');
    await tester.tap(find.bySemanticsLabel('Choose a place'));
    await _settle(tester);
    await tester.tap(find.text('Store ABC'));
    await _settle(tester);

    await tester.tap(find.text('Save price'));
    await _settle(tester);

    final products = await _runAsync(
      tester,
      () => db.select(db.products).get(),
    );
    expect(products.map((p) => p.name), contains('Water'));
    final prices = await _runAsync(
      tester,
      () => db.select(db.priceEntries).get(),
    );
    expect(prices.single.amountMinor, 1250);
    expect(prices.single.placeId, 'abc');
  });

  screenTest('renders in the light theme with animations on', (tester) async {
    await pumpScreen(tester, theme: AppTheme.light(), reduced: false);
    expect(find.text('Save price'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _seedMilka(AppDatabase db) async {
  final products = DriftProductsRepository(db);
  await products.save(
    const Product(
      id: 'm',
      name: 'Milka',
      brand: 'Mondelez',
      variants: [
        Variant(
          id: 'oreo',
          productId: 'm',
          name: 'Oreo',
          sizeValue: 100,
          sizeUnit: SizeUnit.g,
        ),
        Variant(id: 'noisette', productId: 'm', name: 'Noisette'),
      ],
    ),
  );
}

Future<void> _seedPlace(AppDatabase db) => DriftPlacesRepository(db).save(
  Place(
    id: 'abc',
    name: 'Store ABC',
    typeId: builtInId('place_type', 'supermarket'),
  ),
);

/// Drift talks to SQLite on real async time, which the widget tester's fake clock
/// does not drive.
Future<T> _runAsync<T>(WidgetTester tester, Future<T> Function() body) async =>
    (await tester.runAsync(body)) as T;

/// Lets view-model futures (database reads, streams) and animations finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
