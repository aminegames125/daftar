import '../../../../domain/models/money.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/search/normalize_for_search.dart';
import '../../../../domain/use_cases/search_matcher.dart';

/// One buyable catalog entry offered while adding a basket item.
class BasketCandidate {
  const BasketCandidate(this.product, this.variant);

  final Product product;
  final Variant variant;

  /// "Milka" or "Milka · Oreo".
  String get label {
    final v = variant.name?.trim();
    return v == null || v.isEmpty ? product.name : '${product.name} · $v';
  }
}

/// Catalog entries (one per variant) matching [query], best match first and
/// capped at [limit]. A blank query returns nothing: the list only appears once
/// the user types.
List<BasketCandidate> searchCandidates(
  Iterable<Product> products,
  String query, {
  int limit = 6,
}) {
  final q = SearchQuery(query);
  if (q.isEmpty) return const [];
  final ranked = <(BasketCandidate, int)>[];
  for (final p in products) {
    final variants = p.variants.isEmpty ? <Variant?>[null] : p.variants;
    for (final v in variants) {
      final candidate = BasketCandidate(
        p,
        v ?? Variant(id: '', productId: p.id),
      );
      final rank = q.matchAny([
        normalizeForSearch(candidate.label),
        normalizeForSearch('${p.brand ?? ''} ${candidate.label}'),
      ]);
      if (rank != null) ranked.add((candidate, rank.index));
    }
  }
  ranked.sort((a, b) {
    final byRank = a.$2.compareTo(b.$2);
    return byRank != 0 ? byRank : a.$1.label.compareTo(b.$1.label);
  });
  return [for (final (c, _) in ranked.take(limit)) c];
}

/// The price to prefill for a catalog item: the current offer at [placeId] when
/// there is one, otherwise the cheapest current offer anywhere. Null when the
/// product has no price yet.
Money? suggestedPrice(Iterable<PriceEntry> currentOffers, String? placeId) {
  PriceEntry? best;
  for (final e in currentOffers) {
    if (placeId != null && e.placeId == placeId) return e.amount;
    if (best == null || e.amount.compareTo(best.amount) < 0) best = e;
  }
  return best?.amount;
}
