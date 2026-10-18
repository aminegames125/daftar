import '../models/product.dart';
import '../search/normalize_for_search.dart';
import 'search_matcher.dart';

/// Products of one category (when given) whose name, brand or variants match
/// [query]; with an empty query everything in the category, A→Z.
List<Product> filterProducts(
  Iterable<Product> products, {
  String query = '',
  String? categoryId,
}) {
  final q = SearchQuery(query);
  final ranked = <(Product, int)>[];
  for (final p in products) {
    if (categoryId != null && p.categoryId != categoryId) continue;
    var rank = 0;
    if (!q.isEmpty) {
      final keys = [
        normalizeForSearch('${p.name} ${p.brand ?? ''}'),
        for (final v in p.variants)
          normalizeForSearch(
            '${p.name} ${p.brand ?? ''} ${v.name ?? ''} ${v.barcode ?? ''}',
          ),
      ];
      final match = q.matchAny(keys);
      if (match == null) continue;
      rank = match.index;
    }
    ranked.add((p, rank));
  }
  ranked.sort((a, b) {
    final byRank = a.$2.compareTo(b.$2);
    return byRank != 0
        ? byRank
        : normalizeForSearch(a.$1.name)
              .compareTo(normalizeForSearch(b.$1.name));
  });
  return [for (final (p, _) in ranked) p];
}
