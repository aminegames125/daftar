import 'dart:typed_data';

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/open_food_facts_provider.dart';
import 'package:daftar/data/services/open_food_facts_service.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/photo.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/domain/use_cases/best_offer_scorer.dart';
import 'package:daftar/ui/features/prices/view_models/log_price_view_model.dart';
import 'package:daftar/ui/features/prices/view_models/photo_store.dart';
import 'package:daftar/ui/features/prices/view_models/user_location.dart';
import 'package:daftar/ui/features/products/view_models/catalog_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final fixedNow = DateTime(2026, 10, 16, 12);

class FakeOff implements OpenFoodFactsService {
  FakeOff(this.result);
  OffResult result;
  final lookups = <String>[];

  @override
  Future<OffResult> lookup(String barcode) async {
    lookups.add(barcode);
    return result;
  }

  @override
  Future<Uint8List?> downloadImage(String url) async =>
      Uint8List.fromList([1, 2, 3]);
}

class FakePhotoStore implements PhotoStore {
  final imported = <String>[];

  @override
  Future<String> importFile(String sourcePath) async {
    imported.add(sourcePath);
    return '/photos/stored.jpg';
  }

  @override
  Future<String> saveBytes(Uint8List bytes) async => '/photos/off.jpg';
}

void main() {
  late AppDatabase db;
  late FakeOff off;
  late FakePhotoStore photos;
  late ProviderContainer container;

  const args = LogPriceArgs();
  LogPriceViewModel vm() =>
      container.read(logPriceViewModelProvider(args).notifier);
  LogPriceState state() => container.read(logPriceViewModelProvider(args));

  final supermarket = builtInId('place_type', 'supermarket');
  const abc = Place(id: 'abc', name: 'Store ABC', typeId: 'x');

  ProviderContainer makeContainer({LogPriceArgs? forArgs, GeoPoint? location}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => fixedNow),
        userLocationProvider.overrideWith((ref) async => location),
        openFoodFactsServiceProvider.overrideWithValue(off),
        photoStoreProvider.overrideWithValue(photos),
        photoPickerProvider.overrideWithValue((source) async => '/tmp/tag.jpg'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), () => fixedNow.toUtc());
    off = FakeOff(const OffNotFound());
    photos = FakePhotoStore();
    container = makeContainer();
    await container
        .read(placesRepositoryProvider)
        .save(Place(id: 'abc', name: 'Store ABC', typeId: supermarket));
    // Keep the auto-dispose provider alive during the test.
    container.listen(logPriceViewModelProvider(args), (_, _) {});
  });
  tearDown(() => db.close());

  group('validateLogPrice', () {
    test('asks for product, price and a place', () {
      final errors = validateLogPrice(const LogPriceState(), fixedNow);
      expect(
        errors.keys,
        containsAll([
          LogPriceField.product,
          LogPriceField.amount,
          LogPriceField.where,
        ]),
      );
    });

    test('a range needs a highest price that is not below the lowest', () {
      const base = LogPriceState(
        productText: 'Milka',
        amount: Money.tnd(6000),
        isRange: true,
        place: abc,
      );
      expect(validateLogPrice(base, fixedNow).keys, [LogPriceField.amountMax]);
      expect(
        validateLogPrice(
          base.copyWith(amountMax: const Money.tnd(5000)),
          fixedNow,
        ).keys,
        [LogPriceField.amountMax],
      );
      expect(
        validateLogPrice(
          base.copyWith(amountMax: const Money.tnd(8000)),
          fixedNow,
        ),
        isEmpty,
      );
    });

    test(
      'a global price needs a type; a promo end date cannot be in the past',
      () {
        const base = LogPriceState(
          productText: 'Haircut',
          amount: Money.tnd(15000),
          isGlobal: true,
        );
        expect(validateLogPrice(base, fixedNow).keys, [LogPriceField.where]);
        final ok = base.copyWith(globalTypeId: 'ref');
        expect(validateLogPrice(ok, fixedNow), isEmpty);
        final late = ok.copyWith(
          isPromo: true,
          promoEndsAt: DateTime(2026, 10, 1),
        );
        expect(validateLogPrice(late, fixedNow).keys, [LogPriceField.promoEnd]);
        expect(
          validateLogPrice(
            ok.copyWith(isPromo: true, promoEndsAt: DateTime(2026, 10, 16)),
            fixedNow,
          ),
          isEmpty,
        );
      },
    );

    test('zero is not a price', () {
      final errors = validateLogPrice(
        const LogPriceState(productText: 'x', amount: Money.tnd(0), place: abc),
        fixedNow,
      );
      expect(errors.keys, [LogPriceField.amount]);
    });
  });

  group('save', () {
    test('creates the product, its variant and the price', () async {
      vm()
        ..setProductText('Milka')
        ..startNewVariant()
        ..setNewVariantName('Oreo')
        ..setSizeText('100')
        ..setUnit(SizeUnit.g)
        ..setAmount(const Money.tnd(4400))
        ..setPlace(abc);
      expect(state().unitPrice!.label, '= 44.000 TND / kg');

      expect(await vm().save(), isTrue);

      final products = await container
          .read(productsRepositoryProvider)
          .watchAll()
          .first;
      final milka = products.single;
      expect(milka.name, 'Milka');
      expect(milka.variants.single.name, 'Oreo');
      expect(milka.variants.single.baseQuantity, 100);

      final history = await container
          .read(pricesRepositoryProvider)
          .watchHistoryForVariant(milka.variants.single.id)
          .first;
      expect(history.single.amount, const Money.tnd(4400));
      expect(history.single.placeId, 'abc');
      expect(history.single.seenAt.toUtc(), fixedNow.toUtc());
      expect(state().savedEntryId, history.single.id);
    });

    test(
      'a second price for the same product reuses it and keeps both in history',
      () async {
        vm()
          ..setProductText('Milka')
          ..setAmount(const Money.tnd(4400))
          ..setPlace(abc);
        await vm().save();

        vm()
          ..setProductText(
            '  milka ',
          ) // exact name typed again, not picked from the list
          ..setAmount(const Money.tnd(4900));
        expect(await vm().save(), isTrue);

        final products = await container
            .read(productsRepositoryProvider)
            .watchAll()
            .first;
        expect(products, hasLength(1));
        expect(products.single.variants, hasLength(1));
        final history = await container
            .read(pricesRepositoryProvider)
            .watchHistoryForVariant(products.single.variants.single.id)
            .first;
        expect(history, hasLength(2));
      },
    );

    test('range, promo with end date and note are stored', () async {
      vm()
        ..setProductText('Tomatoes')
        ..setAmount(const Money.tnd(1800))
        ..setRange(on: true)
        ..setAmountMax(const Money.tnd(2400))
        ..setPlace(abc)
        ..setPromo(on: true)
        ..setPromoEnd(DateTime(2026, 10, 20))
        ..setNote('  market day  ');
      expect(await vm().save(), isTrue);

      final product =
          (await container.read(productsRepositoryProvider).watchAll().first)
              .single;
      final entry =
          (await container
                  .read(pricesRepositoryProvider)
                  .watchHistoryForVariant(product.variants.single.id)
                  .first)
              .single;
      expect(entry.amountMax, const Money.tnd(2400));
      expect(entry.isPromo, isTrue);
      expect(entry.promoEndsAt, isNotNull);
      expect(entry.note, 'market day');
    });

    test('turning the range off drops the highest price', () async {
      vm()
        ..setRange(on: true)
        ..setAmountMax(const Money.tnd(9000))
        ..setRange(on: false);
      expect(state().amountMax, isNull);
    });

    test('a global price carries its type and no place', () async {
      final types = await container
          .read(globalPriceTypesRepositoryProvider)
          .watchAll()
          .first;
      vm()
        ..setProductText('Haircut')
        ..setAmount(const Money.tnd(15000));
      await vm().useGlobal();
      expect(state().globalTypeId, types.first.id);
      expect(await vm().save(), isTrue);

      final product =
          (await container.read(productsRepositoryProvider).watchAll().first)
              .single;
      final entry =
          (await container
                  .read(pricesRepositoryProvider)
                  .watchHistoryForVariant(product.variants.single.id)
                  .first)
              .single;
      expect(entry.placeId, isNull);
      expect(entry.globalTypeId, types.first.id);
    });

    test('a new global type label can be added and is selected', () async {
      await vm().addGlobalType('Online price');
      final types = await container
          .read(globalPriceTypesRepositoryProvider)
          .watchAll()
          .first;
      expect(types.map((t) => t.name), contains('Online price'));
      expect(
        state().globalTypeId,
        types.firstWhere((t) => t.name == 'Online price').id,
      );
    });

    test(
      'the price photo is copied into the store and linked to the entry',
      () async {
        vm()
          ..setProductText('Milk')
          ..setAmount(const Money.tnd(1500))
          ..setPlace(abc);
        await vm().pickPhoto(PhotoSource.camera);
        expect(state().hasPhoto, isTrue);
        expect(await vm().save(), isTrue);

        expect(photos.imported, ['/tmp/tag.jpg']);
        final saved = await container
            .read(photosRepositoryProvider)
            .watchFor(PhotoOwner.price, state().savedEntryId!)
            .first;
        expect(saved.single.filePath, '/photos/stored.jpg');
      },
    );

    test('invalid forms are not saved and report errors', () async {
      expect(await vm().save(), isFalse);
      expect(state().errors, isNotEmpty);
      expect(
        await container.read(productsRepositoryProvider).watchAll().first,
        isEmpty,
      );
    });

    test('editing a field clears its error', () async {
      await vm().save();
      expect(state().errors, contains(LogPriceField.amount));
      vm().setAmount(const Money.tnd(1000));
      expect(state().errors, isNot(contains(LogPriceField.amount)));
    });
  });

  group('picking an existing product', () {
    test(
      'selecting a variant fills its size; "+ Variant" clears the selection',
      () async {
        final repo = container.read(productsRepositoryProvider);
        const milka = Product(
          id: 'm',
          name: 'Milka',
          variants: [
            Variant(
              id: 'v1',
              productId: 'm',
              name: 'Oreo',
              sizeValue: 100,
              sizeUnit: SizeUnit.g,
            ),
            Variant(
              id: 'v2',
              productId: 'm',
              name: 'Noisette',
              sizeValue: 1.5,
              sizeUnit: SizeUnit.kg,
            ),
          ],
        );
        await repo.save(milka);
        final saved = (await repo.get('m'))!;

        vm().selectProduct(saved);
        expect(state().variantId, 'v1');
        expect(state().sizeText, '100');

        vm().selectVariant('v2');
        expect(state().sizeText, '1.5');
        expect(state().unit, SizeUnit.kg);

        vm().startNewVariant();
        expect(state().variantId, isNull);
        expect(state().newVariantName, '');

        vm().setProductText('Milk');
        expect(state().product, isNull);
      },
    );

    test(
      'a different size on an existing variant makes a new variant',
      () async {
        final repo = container.read(productsRepositoryProvider);
        await repo.save(
          const Product(
            id: 'm',
            name: 'Milka',
            variants: [
              Variant(
                id: 'v1',
                productId: 'm',
                name: 'Oreo',
                sizeValue: 100,
                sizeUnit: SizeUnit.g,
              ),
            ],
          ),
        );
        vm()
          ..selectProduct((await repo.get('m'))!)
          ..setSizeText('300')
          ..setAmount(const Money.tnd(9000))
          ..setPlace(abc);
        await vm().save();

        final variants = (await repo.get('m'))!.variants;
        expect(variants, hasLength(2));
        expect(
          variants.map((v) => v.baseQuantity),
          unorderedEquals([100, 300]),
        );
      },
    );
  });

  group('barcode', () {
    test('a barcode already in the database selects that product without the network', () async {
      final repo = container.read(productsRepositoryProvider);
      await repo.save(
        const Product(
          id: 'm',
          name: 'Milka',
          variants: [
            Variant(
              id: 'v1',
              productId: 'm',
              name: 'Oreo',
              barcode: '6191234567890',
              sizeValue: 100,
              sizeUnit: SizeUnit.g,
            ),
          ],
        ),
      );

      await vm().applyBarcode('6191234567890');

      expect(state().lookup, LookupStatus.foundLocal);
      expect(state().product!.id, 'm');
      expect(state().variantId, 'v1');
      expect(off.lookups, isEmpty);
    });

    test(
      'Open Food Facts fills name, brand, size and downloads the picture',
      () async {
        off.result = const OffFound(
          OffProduct(
            barcode: '6191234567890',
            name: 'Milka Oreo',
            brand: 'Milka',
            imageUrl: 'https://img/a.jpg',
            sizeValue: 100,
            sizeUnit: SizeUnit.g,
          ),
        );

        await vm().applyBarcode('6191234567890');
        await settle();

        final s = state();
        expect(s.lookup, LookupStatus.foundOff);
        expect(s.productText, 'Milka Oreo');
        expect(s.brand, 'Milka');
        expect(s.sizeText, '100');
        expect(s.barcode, '6191234567890');
        expect(s.productPhotoPath, '/photos/off.jpg');
        expect(s.product, isNull);

        vm()
          ..setAmount(const Money.tnd(4400))
          ..setPlace(abc);
        await vm().save();
        final product = (await container
            .read(productsRepositoryProvider)
            .findByBarcode('6191234567890'))!;
        expect(product.brand, 'Milka');
        expect(product.photoPath, '/photos/off.jpg');
      },
    );

    test('offline or unknown barcodes leave the form for typing', () async {
      off.result = const OffUnavailable('timeout');
      await vm().applyBarcode('6191234567890');
      expect(state().lookup, LookupStatus.offline);
      expect(state().barcode, '6191234567890');

      off.result = const OffNotFound();
      await vm().applyBarcode('6191234567890');
      expect(state().lookup, LookupStatus.notFound);
    });
  });

  group('prefill from the route', () {
    test(
      'placeId and productId pre-select the place and the product',
      () async {
        final repo = container.read(productsRepositoryProvider);
        await repo.save(const Product(id: 'm', name: 'Milka'));
        final c = makeContainer();
        const forArgs = LogPriceArgs(placeId: 'abc', productId: 'm');
        c.listen(logPriceViewModelProvider(forArgs), (_, _) {});
        await settle();

        final s = c.read(logPriceViewModelProvider(forArgs));
        expect(s.place?.name, 'Store ABC');
        expect(s.product?.name, 'Milka');
      },
    );

    test('the place you stand in is suggested from the GPS position', () async {
      await container
          .read(placesRepositoryProvider)
          .save(
            Place(
              id: 'near',
              name: 'Near shop',
              typeId: supermarket,
              lat: 36.8,
              lng: 10.18,
            ),
          );
      final c = makeContainer(location: (lat: 36.8002, lng: 10.18));
      c.listen(logPriceViewModelProvider(args), (_, _) {});
      await settle();

      final s = c.read(logPriceViewModelProvider(args));
      expect(s.place?.id, 'near');
      expect(s.placeHint, startsWith('You are here · '));
    });

    test('a place that is far away is not suggested', () async {
      await container
          .read(placesRepositoryProvider)
          .save(
            Place(
              id: 'far',
              name: 'Far shop',
              typeId: supermarket,
              lat: 36.9,
              lng: 10.18,
            ),
          );
      final c = makeContainer(location: (lat: 36.8, lng: 10.18));
      c.listen(logPriceViewModelProvider(args), (_, _) {});
      await settle();
      expect(c.read(logPriceViewModelProvider(args)).place, isNull);
    });
  });
}
