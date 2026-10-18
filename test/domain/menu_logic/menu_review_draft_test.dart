import 'package:daftar/domain/menu_logic/menu_line_parser.dart';
import 'package:daftar/domain/menu_logic/menu_review_draft.dart';
import 'package:daftar/domain/models/ids.dart';
import 'package:daftar/domain/models/menu.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

MenuReviewDraft draftOf(List<String> lines) {
  var n = 0;
  return MenuReviewDraft.fromParsed(
    parseMenuLines([for (final l in lines) OcrLine(l)]),
    idGen: () => 'id${n++}',
  );
}

void main() {
  group('fromParsed', () {
    test('keeps sections, items and option prices as editable text', () {
      final d = draftOf(['Boissons', 'Express 1,8', 'Capucin S 3.2 L 4.0']);
      expect(d.sections.single.name, 'Boissons');
      final items = d.sections.single.items;
      expect(items.map((i) => i.name), ['Express', 'Capucin']);
      expect(items[0].options.single.price, '1.800');
      expect(items[0].options.single.name, '');
      expect(items[1].options.map((o) => '${o.name}:${o.price}'), [
        'S:3.200',
        'L:4.000',
      ]);
      expect(d.itemCount, 2);
      expect(d.canSave, isTrue);
    });

    test('empty scan cannot be saved', () {
      expect(const MenuReviewDraft.empty().canSave, isFalse);
    });
  });

  group('editing', () {
    test('rename, add, remove', () {
      var d = draftOf(['Boissons', 'Express 1,8']);
      final section = d.sections.single;
      final item = section.items.single;
      d = d.renameItem(item.id, 'Espresso');
      d = d.renameSection(section.id, 'Hot');
      d = d.addItem(section.id, id: 'new', optionId: 'newOpt');
      expect(d.sections.single.name, 'Hot');
      expect(d.sections.single.items.map((i) => i.name), ['Espresso', '']);
      d = d.setOption('new', 'newOpt', price: '2,5').renameItem('new', 'Tea');
      expect(
        d.sections.single.items.last.options.single.money,
        const Money.tnd(2500),
      );
      d = d.removeItem(item.id);
      expect(d.itemCount, 1);
      d = d.removeSection(section.id);
      expect(d.sections, isEmpty);
    });

    test('add and remove options, but never the last one', () {
      var d = draftOf(['Express 1,8']);
      final item = d.sections.single.items.single;
      d = d.addOption(item.id, id: 'o2');
      expect(d.sections.single.items.single.options, hasLength(2));
      expect(d.sections.single.items.single.options.map((o) => o.name), [
        'S',
        'L',
      ]);
      d = d.addOption(item.id, id: 'o3');
      expect(d.sections.single.items.single.options.map((o) => o.name), [
        'S',
        'L',
        '',
      ]);
      d = d.removeOption(item.id, 'o3');
      d = d.removeOption(item.id, 'o2');
      d = d.removeOption(
        item.id,
        d.sections.single.items.single.options.single.id,
      );
      expect(d.sections.single.items.single.options, hasLength(1));
    });

    test('toggleUsual flips the star', () {
      var d = draftOf(['Express 1,8']);
      final id = d.sections.single.items.single.id;
      d = d.toggleUsual(id);
      expect(d.sections.single.items.single.isUsual, isTrue);
      d = d.toggleUsual(id);
      expect(d.sections.single.items.single.isUsual, isFalse);
    });

    test('invalid price text blocks saving; empty price does not', () {
      var d = draftOf(['Express 1,8']);
      final item = d.sections.single.items.single;
      final option = item.options.single;
      d = d.setOption(item.id, option.id, price: '1,8x');
      expect(d.invalidPriceCount, 1);
      expect(d.canSave, isFalse);
      d = d.setOption(item.id, option.id, price: '');
      expect(d.canSave, isTrue);
    });

    test('invalid price on a nameless row is ignored', () {
      var d = const MenuReviewDraft.empty().addSection(id: 's');
      d = d
          .addItem('s', id: 'i', optionId: 'o')
          .setOption('i', 'o', price: 'abc');
      expect(d.invalidPriceCount, 0);
      expect(d.canSave, isFalse);
    });
  });

  group('buildMenuSavePlan', () {
    test('single price uses the default option id and plans a price', () {
      final d = draftOf(['Boissons', 'Express 1,8']);
      final plan = buildMenuSavePlan(d, placeId: 'place');
      final item = plan.items.single;
      expect(plan.newSections.single.name, 'Boissons');
      expect(item.sectionId, plan.newSections.single.id);
      expect(item.placeId, 'place');
      expect(item.options.single.id, builtInId('default_option', item.id));
      expect(item.options.single.name, isNull);
      expect(plan.prices.single.menuOptionId, item.options.single.id);
      expect(plan.prices.single.amount, const Money.tnd(1800));
    });

    test('sizes become named options with their own prices', () {
      final plan = buildMenuSavePlan(
        draftOf(['Capucin S 3.2 L 4.0']),
        placeId: 'p',
      );
      final item = plan.items.single;
      expect(item.sectionId, isNull);
      expect(plan.newSections, isEmpty);
      expect(item.options.map((o) => o.name), ['S', 'L']);
      expect(item.options.map((o) => o.sortOrder), [0, 1]);
      expect(plan.prices.map((p) => p.amount), [
        const Money.tnd(3200),
        const Money.tnd(4000),
      ]);
      expect(
        plan.prices.map((p) => p.menuOptionId),
        item.options.map((o) => o.id),
      );
    });

    test('nameless items and empty prices are handled', () {
      var d = draftOf(['Express 1,8']);
      final s = d.sections.single;
      d = d.addItem(s.id, id: 'blank', optionId: 'bo');
      d = d
          .addItem(s.id, id: 'free', optionId: 'fo')
          .renameItem('free', 'Water');
      final plan = buildMenuSavePlan(d, placeId: 'p');
      expect(plan.items.map((i) => i.name), ['Express', 'Water']);
      expect(plan.prices, hasLength(1));
    });

    test('reuses an existing section with a matching name and continues sort orders', () {
      final d = draftOf(['BOISSONS', 'Express 1,8', 'Desserts', 'Tiramisu 7']);
      const existing = MenuSection(
        id: 'sec1',
        placeId: 'p',
        name: 'boissons',
        sortOrder: 0,
      );
      final plan = buildMenuSavePlan(
        d,
        placeId: 'p',
        existingSections: [existing],
        existingSectionCount: 1,
        existingItemCount: 4,
      );
      expect(plan.newSections.map((s) => s.name), ['Desserts']);
      expect(plan.newSections.single.sortOrder, 1);
      expect(plan.items.first.sectionId, 'sec1');
      expect(plan.items.last.sectionId, plan.newSections.single.id);
      expect(plan.items.map((i) => i.sortOrder), [4, 5]);
    });

    test('usual flag is kept', () {
      var d = draftOf(['Express 1,8']);
      d = d.toggleUsual(d.sections.single.items.single.id);
      expect(buildMenuSavePlan(d, placeId: 'p').items.single.isUsual, isTrue);
    });
  });
}
