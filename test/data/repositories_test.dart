import 'package:daftar/data/repositories/categories_repository.dart';
import 'package:daftar/data/repositories/menu_repository.dart';
import 'package:daftar/data/repositories/photos_repository.dart';
import 'package:daftar/data/repositories/place_types_repository.dart';
import 'package:daftar/data/repositories/places_repository.dart';
import 'package:daftar/data/repositories/prices_repository.dart';
import 'package:daftar/data/repositories/products_repository.dart';
import 'package:daftar/data/repositories/settings_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/domain/models/menu.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/photo.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  var clock = DateTime.utc(2026, 10, 16, 12);
  DateTime now() => clock;

  setUp(() {
    clock = DateTime.utc(2026, 10, 16, 12);
    db = AppDatabase(NativeDatabase.memory(), now);
  });
  tearDown(() => db.close());

  final cafe = builtInId('place_type', 'cafe');
  final supermarket = builtInId('place_type', 'supermarket');

  group('SettingsRepository', () {
    test('defaults: dark theme, 90 stale days', () async {
      final repo = DriftSettingsRepository(db);
      expect(await repo.getThemeMode(), ThemeMode.dark);
      expect(await repo.getStaleDays(), 90);
    });

    test(
      'persists theme mode and stale days, overwriting earlier values',
      () async {
        final repo = DriftSettingsRepository(db);
        await repo.setThemeMode(ThemeMode.light);
        await repo.setThemeMode(ThemeMode.system);
        await repo.setStaleDays(60);
        expect(await repo.getThemeMode(), ThemeMode.system);
        expect(await repo.getStaleDays(), 60);
      },
    );

    test('watch emits changes', () async {
      final repo = DriftSettingsRepository(db);
      final values = expectLater(
        repo.watch('k'),
        emitsInOrder([null, 'a', 'b']),
      );
      await Future<void>.delayed(Duration.zero);
      await repo.set('k', 'a');
      await Future<void>.delayed(Duration.zero);
      await repo.set('k', 'b');
      await values;
    });
  });

  group('lookup lists', () {
    test(
      'place types: seeded, can rename built-in, hide, and add custom',
      () async {
        final repo = DriftPlaceTypesRepository(db, now: now);
        var types = await repo.watchAll().first;
        expect(types.where((t) => t.kind == PlaceKind.shop), hasLength(6));
        expect(types.where((t) => t.kind == PlaceKind.venue), hasLength(7));
        expect(types.first.name, 'Supermarket');

        final renamed = PlaceType(
          id: supermarket,
          name: 'Hypermarket',
          iconKey: 'shopping_cart',
          kind: PlaceKind.shop,
          isBuiltIn: true,
        );
        await repo.save(renamed);
        await repo.delete(builtInId('place_type', 'gym'));
        await repo.save(
          PlaceType(
            id: newId(),
            name: 'Kiosk',
            iconKey: 'storefront',
            kind: PlaceKind.shop,
            sortOrder: 99,
          ),
        );

        types = await repo.watchAll().first;
        expect(types.map((t) => t.name), containsAll(['Hypermarket', 'Kiosk']));
        expect(types.map((t) => t.name), isNot(contains('Gym')));
        // A hidden type still resolves by id for places that use it.
        expect((await repo.get(builtInId('place_type', 'gym')))?.name, 'Gym');
      },
    );

    test('categories: soft delete hides from the list', () async {
      final repo = DriftCategoriesRepository(db, now: now);
      final before = await repo.watchAll().first;
      expect(before, hasLength(12));
      await repo.delete(before.last.id);
      expect(await repo.watchAll().first, hasLength(11));
    });
  });

  group('PlacesRepository', () {
    Place place({
      String id = 'p1',
      List<String> tags = const ['Clean'],
      List<String> payments = const [],
    }) => Place(
      id: id,
      name: 'Café Éclair',
      typeId: cafe,
      lat: 36.8,
      lng: 10.18,
      address: 'Rue de Marseille',
      openingHours: const OpeningHours({
        'mon': [
          (open: '08:00', close: '13:00'),
          (open: '15:00', close: '22:00'),
        ],
        'sun': [],
      }),
      wifiName: 'eclair',
      rating: 4,
      paymentMethodIds: payments,
      tags: tags,
    );

    test(
      'round-trips every field incl. hours, payment methods and tags',
      () async {
        final repo = DriftPlacesRepository(db, now: now);
        final cash = builtInId('payment_method', 'cash');
        await repo.save(place(payments: [cash]));

        final loaded = (await repo.get('p1'))!;
        expect(loaded.name, 'Café Éclair');
        expect(loaded.hasLocation, isTrue);
        expect(loaded.rating, 4);
        expect(loaded.paymentMethodIds, [cash]);
        expect(loaded.tags, ['Clean']);
        expect(loaded.openingHours!.days['mon']!.last, (
          open: '15:00',
          close: '22:00',
        ));
        expect(loaded.openingHours!.days['sun'], isEmpty);
        expect(loaded.openingHours!.days.containsKey('tue'), isFalse);
      },
    );

    test(
      'update replaces tags and keeps created_at, bumps updated_at',
      () async {
        final repo = DriftPlacesRepository(db, now: now);
        await repo.save(place());
        clock = clock.add(const Duration(hours: 1));
        await repo.save(place(tags: ['Cheap', 'Quiet']));

        expect(
          (await repo.get('p1'))!.tags,
          unorderedEquals(['Cheap', 'Quiet']),
        );
        final row = await (db.select(db.places)).getSingle();
        expect(
          row.createdAt,
          DateTime.utc(2026, 10, 16, 12).millisecondsSinceEpoch,
        );
        expect(
          row.updatedAt,
          DateTime.utc(2026, 10, 16, 13).millisecondsSinceEpoch,
        );
      },
    );

    test('stores the normalised search key', () async {
      final repo = DriftPlacesRepository(db, now: now);
      await repo.save(place());
      expect(
        (await db.select(db.places).getSingle()).searchKey,
        'cafe eclair rue de marseille',
      );
    });

    test('soft delete hides the place but keeps the row', () async {
      final repo = DriftPlacesRepository(db, now: now);
      await repo.save(place());
      await repo.delete('p1');
      expect(await repo.get('p1'), isNull);
      expect(await repo.watchAll().first, isEmpty);
      expect(await db.select(db.places).get(), hasLength(1));
    });

    test('a place without location (online shop) is valid', () async {
      final repo = DriftPlacesRepository(db, now: now);
      await repo.save(Place(id: 'online', name: 'Jumia', typeId: supermarket));
      expect((await repo.get('online'))!.hasLocation, isFalse);
    });
  });

  group('ProductsRepository', () {
    test(
      'saves variants with normalised base quantity and finds by barcode',
      () async {
        final repo = DriftProductsRepository(db, now: now);
        await repo.save(
          const Product(
            id: 'milka',
            name: 'Milka',
            brand: 'Mondelez',
            variants: [
              Variant(
                id: 'oreo',
                productId: 'milka',
                name: 'Oreo',
                barcode: '111',
                sizeValue: 100,
                sizeUnit: SizeUnit.g,
              ),
              Variant(
                id: 'big',
                productId: 'milka',
                name: 'Noisette',
                barcode: '222',
                sizeValue: 1.5,
                sizeUnit: SizeUnit.kg,
              ),
            ],
          ),
        );

        final rows = await db.select(db.variants).get();
        expect(rows.firstWhere((v) => v.id == 'oreo').baseQuantity, 100);
        expect(rows.firstWhere((v) => v.id == 'big').baseQuantity, 1500);

        final found = await repo.findByBarcode('222');
        expect(found!.name, 'Milka');
        expect(found.variants, hasLength(2));
        expect(await repo.findByBarcode('999'), isNull);
      },
    );

    test(
      'a product without variants gets one stable default variant',
      () async {
        final repo = DriftProductsRepository(db, now: now);
        await repo.save(const Product(id: 'haircut', name: 'Haircut'));
        await repo.save(const Product(id: 'haircut', name: 'Haircut (men)'));

        final product = (await repo.get('haircut'))!;
        expect(product.name, 'Haircut (men)');
        expect(product.variants, hasLength(1));
        expect(
          product.variants.single.id,
          builtInId('default_variant', 'haircut'),
        );
      },
    );

    test('removed variants are soft-deleted; deleting a product hides its variants', () async {
      final repo = DriftProductsRepository(db, now: now);
      await repo.save(
        const Product(
          id: 'p',
          name: 'P',
          variants: [
            Variant(id: 'a', productId: 'p', name: 'A'),
            Variant(id: 'b', productId: 'p', name: 'B'),
          ],
        ),
      );
      await repo.save(
        const Product(
          id: 'p',
          name: 'P',
          variants: [Variant(id: 'a', productId: 'p', name: 'A')],
        ),
      );
      expect((await repo.get('p'))!.variants.map((v) => v.id), ['a']);
      expect(await db.select(db.variants).get(), hasLength(2));

      await repo.delete('p');
      expect(await repo.get('p'), isNull);
      expect(await repo.watchAll().first, isEmpty);
    });

    test('search key covers name, brand, variant and barcode', () async {
      final repo = DriftProductsRepository(db, now: now);
      await repo.save(
        const Product(
          id: 'p',
          name: 'Lait',
          brand: 'Délice',
          variants: [
            Variant(
              id: 'v',
              productId: 'p',
              name: 'Demi-écrémé',
              barcode: '6191',
            ),
          ],
        ),
      );
      expect(
        (await db.select(db.variants).getSingle()).searchKey,
        'lait delice demi-ecreme 6191',
      );
    });
  });

  group('MenuRepository', () {
    Future<void> seedPlace() => DriftPlacesRepository(
      db,
      now: now,
    ).save(Place(id: 'p1', name: 'Café', typeId: cafe));

    test(
      'items keep their options in order; no options → one single-price option',
      () async {
        await seedPlace();
        final repo = DriftMenuRepository(db, now: now);
        await repo.saveSection(
          const MenuSection(id: 's', placeId: 'p1', name: 'Coffee'),
        );
        await repo.saveItem(
          const MenuItem(
            id: 'cap',
            placeId: 'p1',
            sectionId: 's',
            name: 'Capucin',
            options: [
              MenuItemOption(
                id: 'o1',
                menuItemId: 'cap',
                name: 'S',
                sortOrder: 0,
              ),
              MenuItemOption(
                id: 'o2',
                menuItemId: 'cap',
                name: 'L',
                sortOrder: 1,
              ),
            ],
          ),
        );
        await repo.saveItem(
          const MenuItem(
            id: 'water',
            placeId: 'p1',
            name: 'Water',
            sortOrder: 1,
          ),
        );

        final items = await repo.watchItems('p1').first;
        expect(items.map((i) => i.name), ['Capucin', 'Water']);
        expect(items.first.options.map((o) => o.name), ['S', 'L']);
        expect(items.last.options.single.name, isNull);
        expect((await repo.watchSections('p1').first).single.name, 'Coffee');
      },
    );

    test('usual flag, option removal and section/item deletion', () async {
      await seedPlace();
      final repo = DriftMenuRepository(db, now: now);
      await repo.saveSection(
        const MenuSection(id: 's', placeId: 'p1', name: 'Coffee'),
      );
      await repo.saveItem(
        const MenuItem(
          id: 'cap',
          placeId: 'p1',
          sectionId: 's',
          name: 'Capucin',
          options: [
            MenuItemOption(id: 'o1', menuItemId: 'cap', name: 'S'),
            MenuItemOption(
              id: 'o2',
              menuItemId: 'cap',
              name: 'L',
              sortOrder: 1,
            ),
          ],
        ),
      );

      await repo.setUsual('cap', isUsual: true);
      expect((await repo.watchItems('p1').first).single.isUsual, isTrue);

      await repo.saveItem(
        const MenuItem(
          id: 'cap',
          placeId: 'p1',
          sectionId: 's',
          name: 'Capucin',
          isUsual: true,
          options: [MenuItemOption(id: 'o1', menuItemId: 'cap', name: 'S')],
        ),
      );
      expect((await repo.watchItems('p1').first).single.options, hasLength(1));

      await repo.deleteSection('s');
      expect((await repo.watchItems('p1').first).single.sectionId, isNull);
      await repo.deleteItem('cap');
      expect(await repo.watchItems('p1').first, isEmpty);
    });
  });

  group('PricesRepository', () {
    Future<void> seedVariant() async {
      await DriftPlacesRepository(
        db,
        now: now,
      ).save(Place(id: 'a', name: 'Aziza', typeId: supermarket));
      await DriftPlacesRepository(
        db,
        now: now,
      ).save(Place(id: 'b', name: 'Carrefour', typeId: supermarket));
      await DriftProductsRepository(db, now: now).save(
        const Product(
          id: 'p',
          name: 'Milk',
          variants: [Variant(id: 'v', productId: 'p')],
        ),
      );
    }

    PriceEntry entry(
      String id, {
      String? place = 'a',
      int millimes = 1500,
      int daysAgo = 0,
      bool promo = false,
      int? endsInDays,
      int? max,
    }) => PriceEntry(
      id: id,
      variantId: 'v',
      placeId: place,
      globalTypeId: place == null
          ? builtInId('global_price_type', 'reference')
          : null,
      amount: Money.tnd(millimes),
      amountMax: max == null ? null : Money.tnd(max),
      seenAt: clock.subtract(Duration(days: daysAgo)),
      isPromo: promo,
      promoEndsAt: endsInDays == null
          ? null
          : clock.add(Duration(days: endsInDays)),
      note: 'n',
    );

    test('round-trips money, range, promo and times', () async {
      await seedVariant();
      final repo = DriftPricesRepository(db, now: now);
      await repo.save(
        entry('e1', millimes: 6000, max: 8000, promo: true, endsInDays: 3),
      );

      final saved = (await repo.watchHistoryForVariant('v').first).single;
      expect(saved.amount, const Money.tnd(6000));
      expect(saved.amountMax, const Money.tnd(8000));
      expect(saved.isPromo, isTrue);
      expect(
        saved.promoEndsAt!.isAtSameMomentAs(clock.add(const Duration(days: 3))),
        isTrue,
      );
      expect(saved.seenAt.isAtSameMomentAs(clock), isTrue);
      expect(saved.note, 'n');
    });

    test('history keeps every entry, newest first', () async {
      await seedVariant();
      final repo = DriftPricesRepository(db, now: now);
      await repo.save(entry('old', daysAgo: 60, millimes: 1200));
      await repo.save(entry('new', millimes: 1500));
      expect((await repo.watchHistoryForVariant('v').first).map((e) => e.id), [
        'new',
        'old',
      ]);
    });

    test('current offers: newest per place + global, expired promo ignored, deleted ignored', () async {
      await seedVariant();
      final repo = DriftPricesRepository(db, now: now);
      await repo.save(entry('a-old', daysAgo: 40, millimes: 1400));
      await repo.save(
        entry(
          'a-promo',
          daysAgo: 10,
          millimes: 900,
          promo: true,
          endsInDays: -5,
        ),
      );
      await repo.save(entry('b-new', place: 'b', daysAgo: 2));
      await repo.save(entry('b-typo', place: 'b', millimes: 1));
      await repo.delete('b-typo');
      await repo.save(entry('global', place: null, daysAgo: 5));

      final offers = await repo.currentOffersForVariant('v');
      expect(
        offers.map((e) => e.id),
        unorderedEquals(['a-old', 'b-new', 'global']),
      );
      expect(offers.firstWhere((e) => e.id == 'global').isGlobal, isTrue);
    });

    test('menu option prices work like product prices', () async {
      await DriftPlacesRepository(
        db,
        now: now,
      ).save(Place(id: 'p1', name: 'Café', typeId: cafe));
      await DriftMenuRepository(db, now: now).saveItem(
        const MenuItem(
          id: 'cap',
          placeId: 'p1',
          name: 'Capucin',
          options: [MenuItemOption(id: 'o1', menuItemId: 'cap', name: 'S')],
        ),
      );
      final repo = DriftPricesRepository(db, now: now);
      await repo.save(
        PriceEntry(
          id: 'm1',
          menuOptionId: 'o1',
          placeId: 'p1',
          amount: const Money.tnd(3200),
          seenAt: clock,
        ),
      );
      expect(
        (await repo.currentOffersForMenuOption('o1')).single.amount.format(),
        '3.200',
      );
    });
  });

  group('PhotosRepository', () {
    test('lists photos per owner and soft-deletes', () async {
      final repo = DriftPhotosRepository(db, now: now);
      await repo.save(
        const Photo(
          id: '1',
          ownerType: PhotoOwner.menu,
          ownerId: 'p1',
          filePath: 'photos/1.jpg',
          ocrText: 'Café 3.2',
        ),
      );
      await repo.save(
        const Photo(
          id: '2',
          ownerType: PhotoOwner.place,
          ownerId: 'p1',
          filePath: 'photos/2.jpg',
        ),
      );

      final menuPhotos = await repo.watchFor(PhotoOwner.menu, 'p1').first;
      expect(menuPhotos.single.ocrText, 'Café 3.2');
      await repo.delete('1');
      expect(await repo.watchFor(PhotoOwner.menu, 'p1').first, isEmpty);
      expect(await repo.watchFor(PhotoOwner.place, 'p1').first, hasLength(1));
    });
  });
}
