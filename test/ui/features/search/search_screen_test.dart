import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/places_repository.dart';
import 'package:daftar/data/repositories/prices_repository.dart';
import 'package:daftar/data/repositories/products_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/prices/view_models/user_location.dart';
import 'package:daftar/ui/features/products/view_models/catalog_providers.dart';
import 'package:daftar/ui/features/search/view_models/search_view_model.dart';
import 'package:daftar/ui/features/search/views/search_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 16, 12);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory(), () => now.toUtc()));

  void searchTest(
    String name,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await db.close();
        });
      }
    });
  }

  Future<void> seed(WidgetTester tester) => tester
      .runAsync(() async {
        final type = builtInId('place_type', 'supermarket');
        await DriftPlacesRepository(db)
            .save(Place(id: 'abc', name: 'Store ABC', typeId: type));
        await DriftPlacesRepository(db)
            .save(Place(id: 'cbc', name: 'Store CBC', typeId: type));
        await DriftProductsRepository(db).save(
          const Product(
            id: 'milka',
            name: 'Milka',
            variants: [
              Variant(
                id: 'oreo',
                productId: 'milka',
                name: 'Oreo',
                sizeValue: 100,
                sizeUnit: SizeUnit.g,
              ),
            ],
          ),
        );
        final prices = DriftPricesRepository(db);
        await prices.save(
          PriceEntry(
            id: 'p1',
            variantId: 'oreo',
            placeId: 'abc',
            amount: const Money.tnd(4400),
            seenAt: now.subtract(const Duration(days: 3)),
          ),
        );
        await prices.save(
          PriceEntry(
            id: 'p2',
            variantId: 'oreo',
            placeId: 'cbc',
            amount: const Money.tnd(5500),
            seenAt: now.subtract(const Duration(days: 14)),
          ),
        );
      })
      .then((_) {});

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpSearch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => now),
          userLocationProvider.overrideWith((ref) async => null),
          searchDebounceProvider.overrideWithValue(Duration.zero),
        ],
        child: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            size: Size(390, 1400),
          ),
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: SearchScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  searchTest('starts with a hint and the List / Map toggle', (tester) async {
    await pumpSearch(tester);
    expect(find.text('Search prices, places and menus.'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
  });

  searchTest('typing shows the Best option with reasons and the other offers', (
    tester,
  ) async {
    await seed(tester);
    await pumpSearch(tester);

    await tester.enterText(find.byType(TextField), 'milka');
    await settle(tester);
    final st = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
    ).read(searchViewModelProvider);
    expect(st.status, SearchStatus.done);

    expect(find.text('Best option'), findsOneWidget);
    expect(find.text('Store ABC'), findsOneWidget);
    expect(find.text('Cheapest per 100 g'), findsOneWidget);
    expect(find.text('Other offers'), findsOneWidget);
    expect(find.text('Store CBC'), findsOneWidget);
    expect(find.text('4.400'), findsOneWidget);
  });

  searchTest(
    'shows "Searching" while waiting, then an empty state for no match',
    (tester) async {
      await seed(tester);
      await pumpSearch(tester);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump();
      expect(find.textContaining('Searching'), findsOneWidget);

      await settle(tester);
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    },
  );

  searchTest('clearing the box returns to the hint', (tester) async {
    await seed(tester);
    await pumpSearch(tester);
    await tester.enterText(find.byType(TextField), 'milka');
    await settle(tester);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.text('Search prices, places and menus.'), findsOneWidget);
    expect(find.text('Best option'), findsNothing);
  });

  searchTest('the Places filter hides priced products', (tester) async {
    await seed(tester);
    await pumpSearch(tester);
    await tester.enterText(find.byType(TextField), 'store');
    await settle(tester);
    expect(find.text('Places'), findsWidgets);

    await tester.tap(find.text('Products'));
    await settle(tester);
    expect(find.textContaining('No products match'), findsOneWidget);
    expect(find.text('Store ABC'), findsNothing);
  });

  searchTest('recent searches are listed when the box is empty and reusable', (
    tester,
  ) async {
    await seed(tester);
    await pumpSearch(tester);
    await tester.enterText(find.byType(TextField), 'milka');
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
    );
    await tester.runAsync(
      () => container.read(searchViewModelProvider.notifier).remember(),
    );
    await tester.pump();
    expect(container.read(searchViewModelProvider).recents, ['milka']);

    await tester.tap(find.byTooltip('Clear'));
    await settle(tester);
    expect(find.text('Recent searches'), findsOneWidget);

    await tester.tap(find.text('milka'));
    await settle(tester);
    expect(find.text('Best option'), findsOneWidget);
  });

  test('recents keep newest first, no duplicates, capped', () async {
    final c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final vm = c.read(searchViewModelProvider.notifier);
    await vm.remember('milka');
    await vm.remember('cafe');
    await vm.remember('MILKA');
    expect(c.read(searchViewModelProvider).recents, ['MILKA', 'cafe']);
    for (var i = 0; i < 12; i++) {
      await vm.remember('q$i');
    }
    expect(
      c.read(searchViewModelProvider).recents,
      hasLength(kMaxRecentSearches),
    );
    await vm.clearRecents();
    expect(c.read(searchViewModelProvider).recents, isEmpty);
  });
}
