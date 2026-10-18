import 'dart:io';

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/geocoding_location.dart';
import 'package:daftar/data/services/nominatim_client.dart';
import 'package:daftar/data/services/photo_store.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/photo.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/models/price_entry.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/features/places/view_models/address_search_view_model.dart';
import 'package:daftar/ui/features/places/view_models/place_activity.dart';
import 'package:daftar/ui/features/places/view_models/place_form_view_model.dart';
import 'package:daftar/ui/features/places/view_models/places_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

class FakePhotoStore implements PhotoStore {
  final created = <String>[];
  final deleted = <String>[];
  var _n = 0;

  @override
  Future<String?> pick(ImageSource source, {double maxWidth = 1600}) async {
    final path = 'photos/fake${_n++}.jpg';
    created.add(path);
    return path;
  }

  @override
  Future<String> import(String sourcePath) async => sourcePath;

  @override
  Future<File> resolve(String storedPath) async => File(storedPath);

  @override
  Future<void> deleteFile(String storedPath) async => deleted.add(storedPath);
}

class FakeLocation implements LocationService {
  FakeLocation(this.fix);
  final LocationFix fix;

  @override
  Future<LocationFix> currentPosition() async => fix;
}

void main() {
  late AppDatabase db;
  late FakePhotoStore photos;
  late ProviderContainer container;

  ProviderContainer makeContainer({
    LocationService? location,
    NominatimClient? nominatim,
  }) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        photoStoreProvider.overrideWithValue(photos),
        if (location != null)
          locationServiceProvider.overrideWithValue(location),
        if (nominatim != null)
          nominatimClientProvider.overrideWithValue(nominatim),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    photos = FakePhotoStore();
    container = makeContainer();
  });
  tearDown(() => db.close());

  Future<PlaceFormState> loaded(ProviderContainer c, String? id) async {
    final provider = placeFormProvider(id);
    c.listen(provider, (_, _) {});
    while (c.read(provider).loading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return c.read(provider);
  }

  group('PlaceFormNotifier', () {
    test(
      'new place starts with the first type and saves with photos',
      () async {
        final state = await loaded(container, null);
        expect(state.draft.typeId, isNotNull);
        final provider = placeFormProvider(null);
        final form = container.read(provider.notifier);

        expect(await form.save(), isNull);
        expect(container.read(provider).showErrors, isTrue);

        form
          ..setName('Café Yasmine')
          ..setPhone('71 123 456')
          ..setWifiName('Yasmine')
          ..setWifiPassword('abc 123')
          ..setRating(4)
          ..toggleTag('Clean')
          ..addTag('Sea view')
          ..setPosition(36.8, 10.18, address: 'Rue 1')
          ..enableHours(true)
          ..setDayRanges('sun', const []);
        await form.addPhoto(ImageSource.gallery);
        final id = await form.save();
        expect(id, state.draft.id);

        final saved = (await db.select(db.places).get()).single;
        expect(saved.name, 'Café Yasmine');
        expect(saved.rating, 4);
        expect(saved.address, 'Rue 1');
        final place = (await container
            .read(placesRepositoryProvider)
            .get(id!))!;
        expect(place.tags.toSet(), {'Clean', 'Sea view'});
        expect(place.openingHours!.days['sun'], isEmpty);
        final stored = await container
            .read(photosRepositoryProvider)
            .watchFor(PhotoOwner.place, id)
            .first;
        expect(stored.single.filePath, photos.created.single);
      },
    );

    test('edit loads the place and removing a stored photo deletes record and file', () async {
      final typeId = builtInId('place_type', 'cafe');
      await container
          .read(placesRepositoryProvider)
          .save(Place(id: 'p1', name: 'Old', typeId: typeId));
      await container
          .read(photosRepositoryProvider)
          .save(
            const Photo(
              id: 'ph1',
              ownerType: PhotoOwner.place,
              ownerId: 'p1',
              filePath: 'photos/a.jpg',
            ),
          );

      final state = await loaded(container, 'p1');
      expect(state.isEdit, isTrue);
      expect(state.draft.name, 'Old');
      expect(state.photos.single.path, 'photos/a.jpg');

      final form = container.read(placeFormProvider('p1').notifier);
      form.setName('New');
      await form.removePhoto('ph1');
      expect(photos.deleted, isEmpty); // only on save
      await form.save();

      expect(
        (await container.read(placesRepositoryProvider).get('p1'))!.name,
        'New',
      );
      expect(
        await container
            .read(photosRepositoryProvider)
            .watchFor(PhotoOwner.place, 'p1')
            .first,
        isEmpty,
      );
      expect(photos.deleted, ['photos/a.jpg']);
    });

    test(
      'a photo taken but never saved is deleted when the form closes',
      () async {
        await loaded(container, null);
        await container
            .read(placeFormProvider(null).notifier)
            .addPhoto(ImageSource.camera);
        expect(photos.deleted, isEmpty);
        container.dispose();
        expect(photos.deleted, photos.created);
      },
    );

    test(
      'GPS success sets the pin; failure explains and keeps the form usable',
      () async {
        final ok = makeContainer(
          location: FakeLocation(const LocationFix.ok(36.8, 10.18)),
        );
        await loaded(ok, null);
        await ok.read(placeFormProvider(null).notifier).useCurrentLocation();
        expect(ok.read(placeFormProvider(null)).draft.lat, 36.8);

        final denied = makeContainer(
          location: FakeLocation(
            const LocationFix.failure(LocationStatus.permissionDenied),
          ),
        );
        await loaded(denied, null);
        final fix = await denied
            .read(placeFormProvider(null).notifier)
            .useCurrentLocation();
        expect(fix.isOk, isFalse);
        final s = denied.read(placeFormProvider(null));
        expect(s.draft.hasLocation, isFalse);
        expect(s.locationMessage, contains('denied'));
        expect(s.locating, isFalse);
      },
    );

    test('hours can be switched on, edited and off again', () async {
      await loaded(container, null);
      final form = container.read(placeFormProvider(null).notifier);
      form.enableHours(true);
      expect(
        container.read(placeFormProvider(null)).draft.openingHours!.days,
        hasLength(7),
      );
      form.setDayRanges('mon', [(open: '09:00', close: '12:00')]);
      form.copyDayToAllDays('mon');
      expect(
        container.read(placeFormProvider(null)).draft.openingHours!.days['sat'],
        hasLength(1),
      );
      form.enableHours(false);
      expect(
        container.read(placeFormProvider(null)).draft.openingHours,
        isNull,
      );
    });
  });

  group('AddressSearchNotifier', () {
    NominatimClient fake(MockClientHandler handler) => NominatimClient(
      client: MockClient(handler),
      rateLimiter: RateLimiter(minInterval: Duration.zero),
    );

    test('returns results, and reports offline without throwing', () async {
      final ok = makeContainer(
        nominatim: fake(
          (_) async => http.Response(
            '[{"lat":"36.8","lon":"10.1","display_name":"Tunis, Tunisia"}]',
            200,
          ),
        ),
      );
      ok.listen(addressSearchProvider, (_, _) {});
      await ok.read(addressSearchProvider.notifier).search('tunis');
      expect(ok.read(addressSearchProvider).results.single.title, 'Tunis');

      final offline = makeContainer(
        nominatim: fake((_) async => throw http.ClientException('offline')),
      );
      offline.listen(addressSearchProvider, (_, _) {});
      await offline.read(addressSearchProvider.notifier).search('tunis');
      final s = offline.read(addressSearchProvider);
      expect(s.offline, isTrue);
      expect(s.results, isEmpty);
    });
  });

  group('place list', () {
    const cafe = PlaceType(
      id: 'cafe',
      name: 'Café',
      iconKey: 'coffee',
      kind: PlaceKind.venue,
    );
    const shop = PlaceType(
      id: 'shop',
      name: 'Supermarket',
      iconKey: 'cart',
      kind: PlaceKind.shop,
    );
    final entries = [
      const PlaceEntry(
        Place(
          id: '1',
          name: 'Café Yasmine',
          typeId: 'cafe',
          address: 'Rue de Marseille',
        ),
        cafe,
      ),
      const PlaceEntry(Place(id: '2', name: 'Monoprix', typeId: 'shop'), shop),
    ];

    test('filters by accent-insensitive prefix and by type', () {
      expect(
        filterPlaceEntries(
          entries,
          const PlaceListFilter(query: 'cafe'),
        ).map((e) => e.place.id),
        ['1'],
      );
      expect(
        filterPlaceEntries(
          entries,
          const PlaceListFilter(query: 'mar'),
        ).map((e) => e.place.id),
        ['1'],
      );
      expect(
        filterPlaceEntries(
          entries,
          const PlaceListFilter(query: 'super'),
        ).map((e) => e.place.id),
        ['2'],
      );
      expect(
        filterPlaceEntries(
          entries,
          const PlaceListFilter(typeId: 'shop'),
        ).map((e) => e.place.id),
        ['2'],
      );
      expect(
        filterPlaceEntries(entries, const PlaceListFilter(query: 'zzz')),
        isEmpty,
      );
      expect(
        filterPlaceEntries(entries, const PlaceListFilter()),
        hasLength(2),
      );
    });

    test('placeTypeFor falls back for hidden types', () {
      expect(placeTypeFor(const [cafe], 'gone'), unknownPlaceType);
      expect(placeTypeFor(const [cafe], 'cafe'), cafe);
    });
  });

  group('place activity', () {
    test('lists the prices logged at a place, newest first, latest per variant for products', () async {
      final typeId = builtInId('place_type', 'supermarket');
      final places = container.read(placesRepositoryProvider);
      await places.save(Place(id: 'a', name: 'A', typeId: typeId));
      await places.save(Place(id: 'b', name: 'B', typeId: typeId));
      await container
          .read(productsRepositoryProvider)
          .save(
            const Product(
              id: 'milk',
              name: 'Milk',
              variants: [
                Variant(id: 'milk-1l', productId: 'milk', name: '1 L'),
              ],
            ),
          );
      final prices = container.read(pricesRepositoryProvider);
      PriceEntry entry(String id, String place, int millimes, int day) =>
          PriceEntry(
            id: id,
            variantId: 'milk-1l',
            placeId: place,
            amount: Money.tnd(millimes),
            seenAt: DateTime.utc(2026, 10, day),
          );
      await prices.save(entry('1', 'a', 1300, 1));
      await prices.save(entry('2', 'a', 1400, 5));
      await prices.save(entry('3', 'b', 1200, 6));

      final all = await container.read(placeActivityProvider('a').future);
      expect(all.map((a) => a.entry.id), ['2', '1']);
      expect(all.first.title, 'Milk');
      expect(all.first.subtitle, '1 L');

      container.listen(placeProductPricesProvider('a'), (_, _) {});
      await container.read(placeActivityProvider('a').future);
      final latest = container.read(placeProductPricesProvider('a')).value!;
      expect(latest.map((a) => a.entry.id), ['2']);
      expect(latest.single.productId, 'milk');
    });
  });
}
