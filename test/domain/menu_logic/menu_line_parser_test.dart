import 'package:daftar/domain/menu_logic/menu_line_parser.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedMenu parse(List<String> lines, {double? confidence}) =>
    parseMenuLines([for (final l in lines) OcrLine(l, confidence: confidence)]);

Money tnd(String s) => Money.tryParse(s)!;

ParsedMenuItem only(ParsedMenu m) {
  expect(m.itemCount, 1);
  return m.sections.single.items.single;
}

void main() {
  group('price patterns', () {
    test('comma decimal "3,2"', () {
      final item = only(parse(['Capucin 3,2']));
      expect(item.name, 'Capucin');
      expect(item.options.single.price, tnd('3.200'));
      expect(item.options.single.name, isNull);
    });

    test('three decimals with DT suffix', () {
      expect(
        only(parse(['Express  3.200 DT'])).options.single.price,
        tnd('3.2'),
      );
      expect(only(parse(['Express 3.200DT'])).options.single.price, tnd('3.2'));
      expect(
        only(parse(['Express 3.200 tnd'])).options.single.price,
        tnd('3.2'),
      );
    });

    test('whole dinars with d suffix', () {
      expect(only(parse(['Pizza royale 12d'])).options.single.price, tnd('12'));
      expect(
        only(parse(['Pizza royale 12 D'])).options.single.price,
        tnd('12'),
      );
      expect(only(parse(['Pizza royale 12'])).options.single.price, tnd('12'));
    });

    test('leader dots and dashes are removed from the name', () {
      expect(only(parse(['Mojito ........ 8,5'])).name, 'Mojito');
      expect(only(parse(['Mojito -- 8.500'])).name, 'Mojito');
      expect(only(parse(['- Mojito : 8.500'])).name, 'Mojito');
      expect(only(parse(['• Thé à la menthe 2,5'])).name, 'Thé à la menthe');
    });

    test('Arabic-Indic digits are read', () {
      expect(only(parse(['Capucin ٣٫٢'])).options.single.price, tnd('3.2'));
    });

    test('keeps accents and Arabic in names', () {
      expect(only(parse(['Café crème 2,8'])).name, 'Café crème');
      expect(only(parse(['قهوة 2,5'])).name, 'قهوة');
    });

    test('rejects phone numbers, dates, URLs', () {
      expect(parse(['Tel: 71 123 456']).itemCount, 0);
      expect(parse(['Reservations 98 123 456']).itemCount, 0);
      expect(parse(['Since 12/10/2024']).itemCount, 0);
      expect(parse(['www.cafe-yasmine.tn 5']).itemCount, 0);
    });

    test('a number glued to a word is not a price', () {
      expect(parse(['Menu A1']).itemCount, 0);
      expect(parse(['Coca 33cl']).itemCount, 0);
    });

    test('zero price is ignored', () {
      expect(parse(['Free refill 0']).itemCount, 0);
    });

    test('lines without a name are not items', () {
      expect(parse(['---- 3.2']).itemCount, 0);
    });
  });

  group('sizes', () {
    test('two unlabelled prices become S / L', () {
      final item = only(parse(['Capucin 3,2 4,0']));
      expect(item.options.map((o) => o.name), ['S', 'L']);
      expect(item.options.map((o) => o.price), [tnd('3.2'), tnd('4')]);
    });

    test('three unlabelled prices become S / M / L', () {
      expect(only(parse(['Jus 3 4 5'])).options.map((o) => o.name), [
        'S',
        'M',
        'L',
      ]);
    });

    test('explicit labels are kept', () {
      final item = only(parse(['Capucin S 3.2 L 4.0']));
      expect(item.name, 'Capucin');
      expect(item.options.map((o) => o.name), ['S', 'L']);
      expect(item.options.map((o) => o.price), [tnd('3.2'), tnd('4')]);
    });

    test('word labels are capitalised', () {
      final item = only(parse(['Café small 2.0 large 3.0']));
      expect(item.options.map((o) => o.name), ['Small', 'Large']);
    });

    test('separators between prices are tolerated', () {
      final item = only(parse(['Capucin 3,2 / 4,0']));
      expect(item.options.map((o) => o.price), [tnd('3.2'), tnd('4')]);
    });
  });

  group('sections', () {
    test('unpriced line before priced lines is a header', () {
      final m = parse([
        'BOISSONS CHAUDES',
        'Express 1,8',
        'Capucin 3,2',
        'Desserts',
        'Tiramisu 7',
      ]);
      expect(m.sections.map((s) => s.name), ['Boissons chaudes', 'Desserts']);
      expect(m.sections.first.items.map((i) => i.name), ['Express', 'Capucin']);
      expect(m.sections.last.items.single.name, 'Tiramisu');
      expect(m.parsedLines, 5);
      expect(m.isHardToRead, isFalse);
    });

    test('items before any header have no section name', () {
      final m = parse(['Express 1,8', 'Salades', 'Niçoise 9']);
      expect(m.sections.map((s) => s.name), [null, 'Salades']);
    });

    test('header with colon is tidied', () {
      expect(parse(['Pizzas:', 'Margherita 9']).sections.single.name, 'Pizzas');
    });

    test('unpriced lines at the end are ignored', () {
      final m = parse(['Express 1,8', 'Thank you for visiting']);
      expect(m.sections.single.items, hasLength(1));
      expect(m.parsedLines, 1);
      expect(m.totalLines, 2);
    });

    test('overlong text is not a header', () {
      final m = parse([
        'This is a very long sentence that is definitely not a section title',
        'Express 1,8',
      ]);
      expect(m.sections.single.name, isNull);
    });
  });

  group('names and prices on separate lines', () {
    test('name line followed by price-only line', () {
      final m = parse(['Capucin', '3,2', 'Express', '1,8']);
      expect(m.sections.single.items.map((i) => i.name), [
        'Capucin',
        'Express',
      ]);
      expect(m.sections.single.items.first.options.single.price, tnd('3.2'));
      expect(m.isHardToRead, isFalse);
    });

    test('a column of names then a column of prices is zipped', () {
      final m = parse(['Express', 'Capucin', 'Thé', '1,8', '3,2', '2']);
      expect(m.sections.single.items.map((i) => i.name), [
        'Express',
        'Capucin',
        'Thé',
      ]);
      expect(m.sections.single.items.map((i) => i.options.single.price), [
        tnd('1.8'),
        tnd('3.2'),
        tnd('2'),
      ]);
    });

    test('extra leading text before the price column becomes the header', () {
      final m = parse(['Hot drinks', 'Express', 'Capucin', '1,8', '3,2']);
      expect(m.sections.single.name, 'Hot drinks');
      expect(m.sections.single.items.map((i) => i.name), [
        'Express',
        'Capucin',
      ]);
    });

    test('a stray price with nothing before it is dropped', () {
      final m = parse(['3,2', 'Express 1,8']);
      expect(m.itemCount, 1);
    });
  });

  group('confidence rules', () {
    final good = ['Express 1,8', 'Capucin 3,2', 'Thé 2', 'Jus 4'];

    test('clean menu is fine', () {
      final m = parse(good, confidence: 0.9);
      expect(m.isHardToRead, isFalse);
      expect(m.averageConfidence, closeTo(0.9, 1e-9));
      expect(m.parseRatio, 1);
    });

    test('hard to read when fewer than 60% of lines parse', () {
      final m = parse([
        'Express 1,8',
        'welcome to our',
        'lovely little',
        'cafe on the',
        'main street',
      ]);
      expect(m.reasons, contains(HardToReadReason.fewLinesParsed));
      expect(m.isHardToRead, isTrue);
    });

    test('exactly 60% is fine', () {
      final m = parse([
        'Express 1,8',
        'Capucin 3,2',
        'Thé 2',
        'Open daily',
        'Since 1999 here',
      ]);
      expect(m.parseRatio, closeTo(0.6, 1e-9));
      expect(m.reasons, isNot(contains(HardToReadReason.fewLinesParsed)));
    });

    test('Arabic text is hard to read', () {
      final m = parse(['قهوة 2,5', 'شاي 1,5', 'عصير 4']);
      expect(m.reasons, contains(HardToReadReason.arabic));
      expect(m.isHardToRead, isTrue);
    });

    test('a little Arabic among Latin text is tolerated', () {
      final m = parse([
        'Express 1,8',
        'Capucin 3,2',
        'Thé 2',
        'Jus 4',
        'Citronnade 3',
        'Café noir 1,5',
        'Milkshake 6',
        'قهوة 2',
      ]);
      expect(m.reasons, isNot(contains(HardToReadReason.arabic)));
    });

    test('low ML Kit confidence is hard to read', () {
      final m = parse(good, confidence: 0.45);
      expect(m.reasons, contains(HardToReadReason.lowConfidence));
    });

    test('missing confidence is not a reason', () {
      final m = parse(good);
      expect(m.averageConfidence, isNull);
      expect(m.isHardToRead, isFalse);
    });

    test('garbled symbols are hard to read', () {
      final m = parse(['E§pr~ss| 1,8', '~~|| ¢ç¬ ¦¦ 3', 'Th~ ¬¬ 2']);
      expect(m.reasons, contains(HardToReadReason.garbled));
    });

    test('empty scan reports no items', () {
      final m = parse([]);
      expect(m.reasons, {HardToReadReason.noItems});
      expect(m.parseRatio, 0);
      expect(menuHardToReadMessage, contains('hard to read'));
    });

    test('blank and symbol-only lines are not counted', () {
      final m = parse(['', '   ', '---', 'Express 1,8']);
      expect(m.totalLines, 1);
    });
  });

  group('helpers', () {
    test('arabicRatio', () {
      expect(arabicRatio('Express'), 0);
      expect(arabicRatio('قهوة'), 1);
      expect(arabicRatio('٣٢'), 0);
      expect(arabicRatio('ab قه'), closeTo(0.5, 1e-9));
    });

    test('garbledRatio', () {
      expect(garbledRatio('Capucin 3,2 DT'), 0);
      expect(garbledRatio('~~||§§'), 1);
    });
  });
}
