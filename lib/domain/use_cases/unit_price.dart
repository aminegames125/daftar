import '../models/money.dart';
import '../models/product.dart';
import '../search/normalize_for_search.dart';
import 'search_matcher.dart';

/// A price normalised to a reference quantity: per kg, per L or per piece.
class UnitPrice {
  const UnitPrice(this.price, this.suffix);

  final Money price;

  /// "kg", "L" or "pc".
  final String suffix;

  /// "= 44.000 TND / kg".
  String get label => '= ${price.formatWithCode()} / $suffix';
}

/// The price of 1 kg / 1 L / 1 piece for [amount] paid for [size] [unit], or null
/// when it is not meaningful (no size, or the size already is one kg / L / piece).
UnitPrice? unitPriceFor(Money amount, double? size, SizeUnit unit) {
  if (size == null || size <= 0) return null;
  final base = unit.baseQuantity(size);
  if (base <= 0) return null;
  final perBase = unit.dimension == SizeDimension.count ? 1 : 1000;
  if (base == perBase) return null;
  final minor = (amount.minor * perBase / base).round();
  final suffix = switch (unit.dimension) {
    SizeDimension.mass => 'kg',
    SizeDimension.volume => 'L',
    SizeDimension.count => 'pc',
  };
  return UnitPrice(Money(minor, amount.currency), suffix);
}

/// Formats a size for display: "100 g", "1.5 L", "6 pc".
String formatSize(double value, SizeUnit unit) {
  final number = value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
  final symbol = switch (unit) {
    SizeUnit.g => 'g',
    SizeUnit.kg => 'kg',
    SizeUnit.ml => 'ml',
    SizeUnit.l => 'L',
    SizeUnit.pc => 'pc',
  };
  return '$number $symbol';
}

/// Parses a typed size such as "100", "1,5" (null when empty or not positive).
double? parseSize(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  return value != null && value > 0 ? value : null;
}

/// Products whose name, brand or variant names match [query], best match first
/// (exact > prefix > token prefix > contains, then A→Z). Powers the autocomplete
/// on "Log a price".
List<Product> suggestProducts(
  Iterable<Product> products,
  String query, {
  int limit = 5,
}) {
  final q = SearchQuery(query);
  if (q.isEmpty) return const [];
  final ranked = <(Product, MatchRank)>[];
  for (final p in products) {
    final keys = [
      normalizeForSearch(p.name),
      normalizeForSearch('${p.name} ${p.brand ?? ''}'),
      for (final v in p.variants)
        normalizeForSearch('${p.name} ${p.brand ?? ''} ${v.name ?? ''}'),
    ];
    final rank = q.matchAny(keys);
    if (rank != null) ranked.add((p, rank));
  }
  ranked.sort((a, b) {
    final byRank = a.$2.index.compareTo(b.$2.index);
    return byRank != 0
        ? byRank
        : normalizeForSearch(a.$1.name)
              .compareTo(normalizeForSearch(b.$1.name));
  });
  return [for (final (p, _) in ranked.take(limit)) p];
}
