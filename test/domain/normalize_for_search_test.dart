import 'package:daftar/domain/search/normalize_for_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeForSearch', () {
    test('lowercases and trims, collapsing whitespace', () {
      expect(normalizeForSearch('  Milka   OREO '), 'milka oreo');
    });

    test('strips Latin diacritics', () {
      expect(normalizeForSearch('Café Crème Brûlée'), 'cafe creme brulee');
      expect(normalizeForSearch('Œuf à la façon'), 'oeuf a la facon');
    });

    test('unifies Arabic letter variants and drops tashkeel / tatweel', () {
      expect(normalizeForSearch('أحمد'), 'احمد');
      expect(normalizeForSearch('مَدرَسة'), 'مدرسه');
      expect(normalizeForSearch('كــتاب'), 'كتاب');
      expect(normalizeForSearch('مستشفى'), 'مستشفي');
    });

    test('maps Arabic-Indic digits and decimal separator', () {
      expect(normalizeForSearch('٣٫٥٠٠'), '3.500');
      expect(normalizeForSearch('۱۲'), '12');
    });

    test('empty input stays empty', () {
      expect(normalizeForSearch('   '), '');
    });
  });
}
