import 'dart:async';

import 'package:daftar/app/settings.dart';
import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/settings_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/menu.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/features/home/view_models/card_order.dart';
import 'package:daftar/ui/features/home/view_models/home_summary.dart';
import 'package:daftar/ui/features/home/view_models/home_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Waits until [homeSummaryProvider] has data satisfying [test].
  Future<HomeSummary> waitFor(bool Function(HomeSummary) test) {
    final done = Completer<HomeSummary>();
    final sub = container.listen(homeSummaryProvider, (_, next) {
      final value = next.value;
      if (value != null && test(value) && !done.isCompleted) {
        done.complete(value);
      }
    }, fireImmediately: true);
    return done.future
        .timeout(const Duration(seconds: 5))
        .whenComplete(sub.close);
  }

  test('starts empty', () async {
    final s = await waitFor((_) => true);
    expect(s.priceCount, 0);
    expect(s.placeCount, 0);
    expect(s.latest, isNull);
  });

  test(
    'updates live when places, products, prices and menus are saved',
    () async {
      final typeId = builtInId('place_type', 'supermarket');
      final cafeType = builtInId('place_type', 'cafe');

      await container
          .read(placesRepositoryProvider)
          .save(Place(id: 'p1', name: 'Store ABC', typeId: typeId));
      await container
          .read(placesRepositoryProvider)
          .save(Place(id: 'p2', name: 'Café El Houma', typeId: cafeType));
      await container
          .read(productsRepositoryProvider)
          .save(
            const Product(
              id: 'milka',
              name: 'Milka',
              variants: [
                Variant(
                  id: 'v1',
                  productId: 'milka',
                  name: 'Oreo',
                  sizeValue: 100,
                  sizeUnit: SizeUnit.g,
                ),
              ],
            ),
          );
      await container
          .read(pricesRepositoryProvider)
          .save(
            PriceEntry(
              id: 'e1',
              variantId: 'v1',
              placeId: 'p1',
              amount: const Money.tnd(4400),
              seenAt: DateTime(2026, 10, 14),
            ),
          );

      var s = await waitFor((s) => s.priceCount == 1);
      expect(s.placeCount, 2);
      expect(s.latest!.title, 'Milka Oreo 100 g');
      expect(s.latest!.where, 'Store ABC');
      expect(s.latest!.amount, const Money.tnd(4400));
      expect(s.menuPlaceCount, 0);

      // A newer price and a menu item show up without re-reading anything.
      await container
          .read(menuRepositoryProvider)
          .saveItem(
            const MenuItem(
              id: 'i1',
              placeId: 'p2',
              name: 'Capucin',
              options: [MenuItemOption(id: 'o1', menuItemId: 'i1', name: 'S')],
            ),
          );
      await container
          .read(pricesRepositoryProvider)
          .save(
            PriceEntry(
              id: 'e2',
              menuOptionId: 'o1',
              placeId: 'p2',
              amount: const Money.tnd(2800),
              seenAt: DateTime(2026, 10, 15),
            ),
          );
      s = await waitFor((s) => s.priceCount == 2);
      expect(s.menuPlaceCount, 1);
      expect(s.latest!.title, 'Capucin · S');
      expect(s.latest!.isMenu, isTrue);

      // Deleting a place drops it from the count.
      await container.read(placesRepositoryProvider).delete('p2');
      s = await waitFor((s) => s.placeCount == 1);
      expect(s.menuPlaceCount, 0);
    },
  );

  group('card order', () {
    test('parseCardOrder drops unknown names and appends missing cards', () {
      expect(parseCardOrder(null), HomeCardId.values);
      expect(parseCardOrder(''), HomeCardId.values);
      expect(parseCardOrder('menus,prices,bogus,menus'), [
        HomeCardId.menus,
        HomeCardId.prices,
        HomeCardId.places,
        HomeCardId.calculator,
        HomeCardId.accounts,
      ]);
    });

    test('moving a card updates state and is saved in settings', () async {
      container.read(homeCardOrderProvider); // build
      await container.read(homeCardOrderProvider.notifier).move(0, 2);
      expect(container.read(homeCardOrderProvider).take(3), [
        HomeCardId.places,
        HomeCardId.menus,
        HomeCardId.prices,
      ]);
      expect(
        await DriftSettingsRepository(db).get(AppSettingKeys.homeCardOrder),
        'places,menus,prices,calculator,accounts',
      );
    });

    test('a saved order is loaded', () async {
      await DriftSettingsRepository(db)
          .set(AppSettingKeys.homeCardOrder, 'accounts,prices');
      container.read(homeCardOrderProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(container.read(homeCardOrderProvider).first, HomeCardId.accounts);
      expect(
        container.read(homeCardOrderProvider),
        hasLength(HomeCardId.values.length),
      );
    });
  });
}
