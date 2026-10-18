import 'dart:io';

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/data/services/ocr_service.dart';
import 'package:daftar/data/services/photo_store.dart';
import 'package:daftar/domain/menu_logic/menu_line_parser.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/models/photo.dart';
import 'package:daftar/domain/models/place.dart';
import 'package:daftar/ui/features/menus/view_models/menu_snap_view_model.dart';
import 'package:daftar/ui/features/menus/view_models/menu_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class FakePhotoStore implements PhotoStore {
  final deleted = <String>[];
  var _n = 0;

  @override
  Future<String?> pick(ImageSource source, {double maxWidth = 1600}) async =>
      'photos/m${_n++}.jpg';

  @override
  Future<String> import(String sourcePath) async => sourcePath;

  @override
  Future<File> resolve(String storedPath) async => File(storedPath);

  @override
  Future<void> deleteFile(String storedPath) async => deleted.add(storedPath);
}

class FakeOcr implements OcrService {
  FakeOcr(this.lines, {this.fail = false});

  final List<OcrLine> lines;
  final bool fail;

  @override
  Future<OcrResult> recognize(String imagePath) async {
    if (fail) throw StateError('no model');
    return OcrResult(text: lines.map((l) => l.text).join('\n'), lines: lines);
  }
}

void main() {
  late AppDatabase db;
  late FakePhotoStore photos;

  ProviderContainer make({OcrService? ocr}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        photoStoreProvider.overrideWithValue(photos),
        if (ocr != null) ocrServiceProvider.overrideWithValue(ocr),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> addPlace(ProviderContainer c) => c
      .read(placesRepositoryProvider)
      .save(
        Place(id: 'p', name: 'Café', typeId: builtInId('place_type', 'cafe')),
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    photos = FakePhotoStore();
  });
  tearDown(() => db.close());

  group('MenuActions', () {
    test('saves an item with sizes; each option price is a price entry; unchanged prices are not repeated', () async {
      final c = make();
      await addPlace(c);
      final actions = c.read(menuActionsProvider('p'));

      final id = await actions.saveItem(
        name: ' Capucin ',
        options: [
          const OptionInput(name: 'S', price: Money.tnd(3200)),
          const OptionInput(name: 'L', price: Money.tnd(4000)),
        ],
        isUsual: true,
      );
      final items = await c.read(menuRepositoryProvider).watchItems('p').first;
      expect(items.single.name, 'Capucin');
      expect(items.single.isUsual, isTrue);
      expect(items.single.options.map((o) => o.name), ['S', 'L']);

      final sOption = items.single.options.first;
      final prices = c.read(pricesRepositoryProvider);
      expect(
        await prices.watchHistoryForMenuOption(sOption.id).first,
        hasLength(1),
      );

      // Edit: S keeps its price, L goes up.
      await actions.saveItem(
        itemId: id,
        name: 'Capucin',
        isUsual: true,
        options: [
          OptionInput(id: sOption.id, name: 'S', price: const Money.tnd(3200)),
          OptionInput(
            id: items.single.options.last.id,
            name: 'L',
            price: const Money.tnd(4200),
          ),
        ],
      );
      expect(
        await prices.watchHistoryForMenuOption(sOption.id).first,
        hasLength(1),
      );
      final lHistory = await prices
          .watchHistoryForMenuOption(items.single.options.last.id)
          .first;
      expect(lHistory.map((e) => e.amount), [
        const Money.tnd(4200),
        const Money.tnd(4000),
      ]);
    });

    test('single price item uses the default option; sections group items; menuData shows prices and usual', () async {
      final c = make();
      await addPlace(c);
      final actions = c.read(menuActionsProvider('p'));
      await actions.addSection('Drinks');
      final section =
          (await c.read(menuRepositoryProvider).watchSections('p').first)
              .single;
      await actions.saveItem(
        name: 'Express',
        sectionId: section.id,
        options: [const OptionInput(price: Money.tnd(1800))],
        isUsual: true,
      );
      await actions.saveItem(name: 'Water', options: const [OptionInput()]);

      c.listen(menuDataProvider('p'), (_, _) {});
      c.listen(menuLatestPricesProvider('p'), (_, _) {});
      await c.read(menuLatestPricesProvider('p').future);
      final data = c.read(menuDataProvider('p')).value!;
      expect(data.sections.map((s) => s.section?.name), [null, 'Drinks']);
      expect(data.sections.first.items.single.item.name, 'Water');
      expect(data.sections.first.items.single.lowestPrice, isNull);
      final express = data.sections.last.items.single;
      expect(express.lowestPrice, const Money.tnd(1800));
      expect(express.hasSizes, isFalse);
      expect(data.usual.map((i) => i.item.name), ['Express']);
    });

    test('setUsual and deleteItem', () async {
      final c = make();
      await addPlace(c);
      final actions = c.read(menuActionsProvider('p'));
      final id = await actions.saveItem(
        name: 'Tea',
        options: [const OptionInput(price: Money.tnd(2000))],
      );
      await actions.setUsual(id, isUsual: true);
      expect(
        (await c.read(menuRepositoryProvider).watchItems('p').first)
            .single
            .isUsual,
        isTrue,
      );
      await actions.deleteItem(id);
      expect(
        await c.read(menuRepositoryProvider).watchItems('p').first,
        isEmpty,
      );
    });
  });

  group('MenuSnapNotifier', () {
    final lines = [
      const OcrLine('Boissons', confidence: 0.9),
      const OcrLine('Express 1,8', confidence: 0.9),
      const OcrLine('Capucin S 3.2 L 4.0', confidence: 0.9),
    ];

    Future<void> waitForReview(ProviderContainer c) async {
      while (c.read(menuSnapProvider('p')).phase == SnapPhase.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test(
      'scan, review, save writes menu, prices and the photo with its OCR text',
      () async {
        final c = make(ocr: FakeOcr(lines));
        await addPlace(c);
        c.listen(menuSnapProvider('p'), (_, _) {});
        final snap = c.read(menuSnapProvider('p').notifier);

        await snap.capture(ImageSource.camera);
        await waitForReview(c);
        var state = c.read(menuSnapProvider('p'));
        expect(state.phase, SnapPhase.review);
        expect(state.hardToRead, isFalse);
        expect(state.draft.itemCount, 2);

        // The user fixes a typo before saving.
        final express = state.draft.sections.single.items.first;
        snap.edit((d) => d.renameItem(express.id, 'Espresso'));
        expect(await snap.save(), isTrue);
        state = c.read(menuSnapProvider('p'));
        expect(state.phase, SnapPhase.saved);
        expect(state.progress, 1);

        final repo = c.read(menuRepositoryProvider);
        final items = await repo.watchItems('p').first;
        expect(items.map((i) => i.name), ['Espresso', 'Capucin']);
        expect((await repo.watchSections('p').first).single.name, 'Boissons');
        final capucin = items.last;
        expect(capucin.options.map((o) => o.name), ['S', 'L']);
        final history = await c
            .read(pricesRepositoryProvider)
            .watchHistoryForMenuOption(capucin.options.last.id)
            .first;
        expect(history.single.amount, const Money.tnd(4000));
        expect(history.single.placeId, 'p');

        final stored = await c
            .read(photosRepositoryProvider)
            .watchFor(PhotoOwner.menu, 'p')
            .first;
        expect(stored.single.filePath, 'photos/m0.jpg');
        expect(stored.single.ocrText, contains('Capucin'));
        expect(photos.deleted, isEmpty);
      },
    );

    test('hard-to-read scans are flagged', () async {
      final c = make(
        ocr: FakeOcr([
          const OcrLine('قهوة 2,5', confidence: 0.9),
          const OcrLine('شاي 1,5', confidence: 0.9),
        ]),
      );
      c.listen(menuSnapProvider('p'), (_, _) {});
      await c.read(menuSnapProvider('p').notifier).capture(ImageSource.gallery);
      await waitForReview(c);
      final state = c.read(menuSnapProvider('p'));
      expect(state.hardToRead, isTrue);
      expect(state.reasons, contains(HardToReadReason.arabic));
    });

    test('OCR failure falls back to typing with a blank row', () async {
      final c = make(ocr: FakeOcr(const [], fail: true));
      c.listen(menuSnapProvider('p'), (_, _) {});
      await c.read(menuSnapProvider('p').notifier).capture(ImageSource.gallery);
      await waitForReview(c);
      final state = c.read(menuSnapProvider('p'));
      expect(state.phase, SnapPhase.review);
      expect(state.hardToRead, isTrue);
      expect(state.error, isNotNull);
      expect(state.draft.sections.single.items, hasLength(1));
      expect(state.draft.canSave, isFalse);
    });

    test('an unsaved photo is deleted when the flow is abandoned', () async {
      final c = make(ocr: FakeOcr(lines));
      c.listen(menuSnapProvider('p'), (_, _) {});
      await c.read(menuSnapProvider('p').notifier).capture(ImageSource.camera);
      await waitForReview(c);
      c.dispose();
      expect(photos.deleted, ['photos/m0.jpg']);
    });

    test('save is refused while the draft has an invalid price', () async {
      final c = make(ocr: FakeOcr(lines));
      c.listen(menuSnapProvider('p'), (_, _) {});
      final snap = c.read(menuSnapProvider('p').notifier);
      await snap.capture(ImageSource.camera);
      await waitForReview(c);
      final item = c
          .read(menuSnapProvider('p'))
          .draft
          .sections
          .single
          .items
          .first;
      snap.edit(
        (d) => d.setOption(item.id, item.options.single.id, price: 'abc'),
      );
      expect(await snap.save(), isFalse);
      expect(c.read(menuSnapProvider('p')).phase, SnapPhase.review);
    });

    test('typing it yourself skips scanning', () async {
      final c = make();
      c.listen(menuSnapProvider('p'), (_, _) {});
      c.read(menuSnapProvider('p').notifier).typeItYourself();
      final state = c.read(menuSnapProvider('p'));
      expect(state.phase, SnapPhase.review);
      expect(state.typedByHand, isTrue);
      expect(state.photoPath, isNull);
    });
  });
}
