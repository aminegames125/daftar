import '../models/money.dart';

/// One line of recognised text. [confidence] is ML Kit's 0..1 value when the
/// platform reports one.
class OcrLine {
  const OcrLine(this.text, {this.confidence});

  final String text;
  final double? confidence;
}

/// Why a scan is shown with "This one's hard to read".
enum HardToReadReason {
  noItems,
  fewLinesParsed,
  arabic,
  lowConfidence,
  garbled,
}

/// A size / option with its own price. [name] is null for a single-price item.
class ParsedOption {
  const ParsedOption({this.name, required this.price});

  final String? name;
  final Money price;
}

class ParsedMenuItem {
  const ParsedMenuItem({required this.name, required this.options});

  final String name;

  /// At least one. One option = single price (name null).
  final List<ParsedOption> options;
}

class ParsedMenuSection {
  const ParsedMenuSection({this.name, required this.items});

  /// null for items found before any header.
  final String? name;
  final List<ParsedMenuItem> items;
}

class ParsedMenu {
  const ParsedMenu({
    required this.sections,
    required this.totalLines,
    required this.parsedLines,
    required this.averageConfidence,
    required this.reasons,
  });

  final List<ParsedMenuSection> sections;

  /// Lines that carried text worth reading.
  final int totalLines;

  /// Lines turned into a header or an item (name or price).
  final int parsedLines;

  /// Mean of the lines' ML Kit confidences, null when none were reported.
  final double? averageConfidence;
  final Set<HardToReadReason> reasons;

  int get itemCount => sections.fold(0, (n, s) => n + s.items.length);

  /// Share of readable lines that were understood, 0..1.
  double get parseRatio => totalLines == 0 ? 0 : parsedLines / totalLines;

  /// Show "This one's hard to read. Typing it yourself will be more accurate."
  bool get isHardToRead => reasons.isNotEmpty;
}

/// Tunables (DATA_MODEL § 8).
abstract final class MenuParserConfig {
  /// Hard to read when fewer than this share of lines parse.
  static const minParseRatio = 0.6;

  /// Hard to read when ML Kit's mean confidence is below this.
  static const minConfidence = 0.6;

  /// Hard to read when this share of letters is Arabic.
  static const maxArabicRatio = 0.15;

  /// Hard to read when this share of characters is odd symbols (blurry scans).
  static const maxGarbledRatio = 0.25;

  /// Header lines longer than this are treated as noise.
  static const maxHeaderLength = 40;
}

/// True for Arabic-script letters (not Arabic-Indic digits).
bool isArabicLetter(int rune) =>
    (rune >= 0x0600 &&
        rune <= 0x06FF &&
        !(rune >= 0x0660 && rune <= 0x0669) &&
        !(rune >= 0x06F0 && rune <= 0x06F9)) ||
    (rune >= 0x0750 && rune <= 0x077F) ||
    (rune >= 0xFB50 && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF);

bool _isLetter(int rune) {
  if (isArabicLetter(rune)) return true;
  // Latin letters incl. accents (Latin-1 supplement + Latin Extended-A/B).
  return (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      (rune >= 0xC0 && rune <= 0x24F && rune != 0xD7 && rune != 0xF7);
}

/// Share of letters in [text] that are Arabic (0 when there are no letters).
double arabicRatio(String text) {
  var letters = 0;
  var arabic = 0;
  for (final r in text.runes) {
    if (!_isLetter(r)) continue;
    letters++;
    if (isArabicLetter(r)) arabic++;
  }
  return letters == 0 ? 0 : arabic / letters;
}

/// Share of non-space characters that are neither letters, digits nor the
/// punctuation a menu normally contains. High values mean blurry / garbled OCR.
double garbledRatio(String text) {
  var total = 0;
  var odd = 0;
  for (final r in text.runes) {
    if (r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D) continue;
    total++;
    if (_isLetter(r)) continue;
    if (r >= 0x30 && r <= 0x39) continue;
    if (r >= 0x0660 && r <= 0x0669) continue;
    if ('.,:;-–—_/()&+%!?\'"€\$·•*…@#'.contains(String.fromCharCode(r))) {
      continue;
    }
    odd++;
  }
  return total == 0 ? 0 : odd / total;
}

String _asciiDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0x066B) {
      b.write('.');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

// "3,2", "3.200", "12", optionally followed by dt / tnd / d / dinar(s), optionally
// preceded by a size label ("S", "L", "Small"…), anchored at the end of the line.
final _tailPrice = RegExp(
  r'^(.*?)(?<=^|[\s.\-–:·…_/|])'
  r'(?:(s|m|l|xl|xxl|small|medium|large|petit|moyen|grand|simple|double)\s*[:=\-]?\s*)?'
  r'(\d{1,3}(?:[.,]\d{1,3})?)\s*(?:dt|tnd|d|din|dinars?)?\s*$',
  caseSensitive: false,
);

final _notAMenuLine = RegExp(
  r'(?:\b(?:tel|tél|gsm|fax|www|http|wifi|wi-fi)\b|@|\.com\b|\.tn\b|(?:\d[\s.\-/]?){8,})',
  caseSensitive: false,
);

final _separatorsAtEnd = RegExp(r'[\s/|,\-–·.:_…]+$');
final _bulletsAtStart = RegExp(r'^[\s\-–•*·>]+');

typedef _Price = ({String? label, Money price});

/// Splits "Capucin ..... 3,2" into a name and its prices. Returns null when the
/// line does not end with a price. The name may be empty (price-only line).
({String name, List<_Price> prices})? _splitPrices(String line) {
  if (_notAMenuLine.hasMatch(line)) return null;
  var rest = line;
  final prices = <_Price>[];
  while (true) {
    final m = _tailPrice.firstMatch(rest);
    if (m == null) break;
    final money = Money.tryParse(m[3]!);
    if (money == null || money.minor <= 0) break;
    prices.insert(0, (label: m[2], price: money));
    rest = m[1]!.replaceFirst(_separatorsAtEnd, '');
    if (rest.isEmpty) break;
  }
  if (prices.isEmpty) return null;
  return (name: rest.replaceFirst(_bulletsAtStart, '').trim(), prices: prices);
}

bool _hasNameChars(String s) => RegExp(r'[A-Za-zÀ-ɏ؀-ۿ]{2}').hasMatch(s);

List<ParsedOption> _options(List<_Price> prices) {
  if (prices.length == 1) return [ParsedOption(price: prices.single.price)];
  const defaults = {
    2: ['S', 'L'],
    3: ['S', 'M', 'L'],
  };
  final fallback = defaults[prices.length];
  return [
    for (var i = 0; i < prices.length; i++)
      ParsedOption(
        name: prices[i].label != null
            ? _labelName(prices[i].label!)
            : (fallback?[i] ?? 'Option ${i + 1}'),
        price: prices[i].price,
      ),
  ];
}

String _labelName(String label) {
  final l = label.trim();
  if (l.length <= 3) return l.toUpperCase();
  return l[0].toUpperCase() + l.substring(1).toLowerCase();
}

String _tidyHeader(String raw) {
  var s = raw
      .replaceFirst(_bulletsAtStart, '')
      .replaceFirst(_separatorsAtEnd, '')
      .trim();
  final letters = s.runes.where(_isLetter).length;
  final upper = RegExp(r'[A-ZÀ-Þ]').allMatches(s).length;
  // "BOISSONS CHAUDES" → "Boissons chaudes".
  if (letters > 3 && upper == letters) s = s[0] + s.substring(1).toLowerCase();
  return s;
}

bool _looksLikeHeader(String s) {
  if (s.length < 2 || s.length > MenuParserConfig.maxHeaderLength) return false;
  if (!_hasNameChars(s)) return false;
  if (_notAMenuLine.hasMatch(s)) return false;
  return !RegExp(r'\d{4,}').hasMatch(s);
}

enum _Kind { item, priceOnly, text }

class _Classified {
  _Classified(this.kind, this.text, {this.name = '', this.prices = const []});

  final _Kind kind;
  final String text;
  final String name;
  final List<_Price> prices;
}

/// Turns recognised lines into sections / items / prices (DATA_MODEL § 8).
///
/// * A line ending in a price (`3,2`, `3.200 DT`, `12d`, `S 3.2 L 4`) is an item.
/// * A text line followed by a price-only line, or a run of names followed by a
///   run of prices (two-column menus), is paired up.
/// * Text right before priced lines is a section header.
/// * Hard to read when < 60% of lines parse, Arabic is detected, ML Kit
///   confidence is low, or the text is garbled.
ParsedMenu parseMenuLines(List<OcrLine> lines) {
  final classified = <_Classified>[];
  final confidences = <double>[];
  final allText = StringBuffer();

  for (final line in lines) {
    final text = _asciiDigits(line.text).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    allText.writeln(text);
    // Lines with no letters or digits at all (stray marks) are not worth counting.
    if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) continue;
    if (line.confidence != null) confidences.add(line.confidence!);

    final split = _splitPrices(text);
    if (split == null) {
      classified.add(_Classified(_Kind.text, text));
    } else if (split.name.isEmpty) {
      classified.add(_Classified(_Kind.priceOnly, text, prices: split.prices));
    } else if (_hasNameChars(split.name)) {
      classified.add(
        _Classified(_Kind.item, text, name: split.name, prices: split.prices),
      );
    } else {
      classified.add(_Classified(_Kind.text, text));
    }
  }

  final sections = <ParsedMenuSection>[];
  String? currentName;
  var current = <ParsedMenuItem>[];
  var parsed = 0;

  void flush() {
    if (current.isNotEmpty) {
      sections.add(ParsedMenuSection(name: currentName, items: current));
    }
    current = [];
  }

  void startSection(String header) {
    flush();
    currentName = _tidyHeader(header);
    parsed++;
  }

  var i = 0;
  while (i < classified.length) {
    final c = classified[i];
    switch (c.kind) {
      case _Kind.item:
        current.add(ParsedMenuItem(name: c.name, options: _options(c.prices)));
        parsed++;
        i++;
      case _Kind.priceOnly:
        i++; // nothing to attach it to
      case _Kind.text:
        var j = i;
        while (j < classified.length && classified[j].kind == _Kind.text) {
          j++;
        }
        final texts = classified.sublist(i, j);
        var k = j;
        while (k < classified.length && classified[k].kind == _Kind.priceOnly) {
          k++;
        }
        final priceRun = classified.sublist(j, k);
        final pairCount = priceRun.length < texts.length
            ? priceRun.length
            : texts.length;
        final unpaired = texts.length - pairCount;

        // Leading texts: the last one may head a new section when something follows.
        if (unpaired > 0) {
          final header = texts[unpaired - 1].text;
          final followedByItems =
              pairCount > 0 ||
              (j < classified.length && classified[j].kind == _Kind.item);
          if (followedByItems && _looksLikeHeader(header)) startSection(header);
        }
        for (var n = 0; n < pairCount; n++) {
          final name = texts[unpaired + n].text
              .replaceFirst(_bulletsAtStart, '')
              .replaceFirst(_separatorsAtEnd, '')
              .trim();
          final prices = priceRun[n].prices;
          if (_hasNameChars(name)) {
            current.add(ParsedMenuItem(name: name, options: _options(prices)));
            parsed += 2;
          }
        }
        i = pairCount > 0 ? k : j;
    }
  }
  flush();

  final total = classified.length;
  final avg = confidences.isEmpty
      ? null
      : confidences.reduce((a, b) => a + b) / confidences.length;
  final text = allText.toString();

  final reasons = <HardToReadReason>{};
  final itemCount = sections.fold<int>(0, (n, s) => n + s.items.length);
  if (itemCount == 0) reasons.add(HardToReadReason.noItems);
  if (total > 0 && parsed / total < MenuParserConfig.minParseRatio) {
    reasons.add(HardToReadReason.fewLinesParsed);
  }
  if (arabicRatio(text) >= MenuParserConfig.maxArabicRatio) {
    reasons.add(HardToReadReason.arabic);
  }
  if (avg != null && avg < MenuParserConfig.minConfidence) {
    reasons.add(HardToReadReason.lowConfidence);
  }
  if (garbledRatio(text) >= MenuParserConfig.maxGarbledRatio) {
    reasons.add(HardToReadReason.garbled);
  }

  return ParsedMenu(
    sections: sections,
    totalLines: total,
    parsedLines: parsed > total ? total : parsed,
    averageConfidence: avg,
    reasons: reasons,
  );
}

/// The message shown when [ParsedMenu.isHardToRead].
const menuHardToReadMessage =
    "This one's hard to read. Typing it yourself will be more accurate.";
