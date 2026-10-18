/// Normalises text for accent/diacritic-insensitive search (DATA_MODEL § 6).
///
/// Applied to every stored `search_key` and to the user's query.
String normalizeForSearch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final mapped = _map[rune];
    if (mapped != null) {
      buffer.write(mapped);
    } else if (_dropped(rune)) {
      continue;
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Tashkeel (U+064B–U+0652), superscript alef (U+0670) and tatweel (U+0640).
bool _dropped(int rune) =>
    (rune >= 0x064B && rune <= 0x0652) || rune == 0x0670 || rune == 0x0640;

final Map<int, String> _map = _build();

Map<int, String> _build() {
  final map = <int, String>{};
  void add(String chars, String to) {
    for (final rune in chars.runes) {
      map[rune] = to;
    }
  }

  // Latin diacritics.
  add('àáâãäå', 'a');
  add('ç', 'c');
  add('èéêë', 'e');
  add('ìíîï', 'i');
  add('ñ', 'n');
  add('òóôõö', 'o');
  add('ùúûü', 'u');
  add('ýÿ', 'y');
  add('œ', 'oe');
  add('æ', 'ae');
  // Arabic letter variants.
  add('أإآٱ', 'ا');
  add('ى', 'ي');
  add('ة', 'ه');
  add('ؤ', 'و');
  add('ئ', 'ي');
  // Arabic-Indic and Persian digits, Arabic decimal separator.
  for (var i = 0; i < 10; i++) {
    map[0x0660 + i] = '$i';
    map[0x06F0 + i] = '$i';
  }
  map[0x066B] = '.';
  return map;
}
