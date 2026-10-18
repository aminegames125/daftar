import '../search/normalize_for_search.dart';

/// How well a query matches a stored `search_key` (lower index is better).
enum MatchRank {
  /// The whole key equals the query.
  exact,

  /// The key starts with the query.
  prefix,

  /// Every query token is the start of some token of the key
  /// ("mil oreo" finds "milka oreo").
  tokenPrefix,

  /// Every query token appears somewhere inside the key ("reo" in "oreo").
  contains,
}

/// A query ready to be matched against many candidates (DATA_MODEL § 6).
class SearchQuery {
  SearchQuery(String raw)
    : normalized = normalizeForSearch(raw),
      tokens = normalizeForSearch(raw)
          .split(' ')
          .where((t) => t.isNotEmpty)
          .toList();

  final String normalized;
  final List<String> tokens;

  bool get isEmpty => tokens.isEmpty;

  /// Rank of [key] (an already-normalised search key), or null when it does not match.
  MatchRank? match(String key) {
    if (isEmpty || key.isEmpty) return null;
    if (key == normalized) return MatchRank.exact;
    if (key.startsWith(normalized)) return MatchRank.prefix;
    final keyTokens = key.split(' ');
    if (tokens.every((q) => keyTokens.any((k) => k.startsWith(q)))) {
      return MatchRank.tokenPrefix;
    }
    if (tokens.every(key.contains)) return MatchRank.contains;
    return null;
  }

  /// Best rank over several keys (a name, a brand, a variant, …).
  MatchRank? matchAny(Iterable<String> keys) {
    MatchRank? best;
    for (final key in keys) {
      final rank = match(key);
      if (rank != null && (best == null || rank.index < best.index)) {
        best = rank;
      }
    }
    return best;
  }
}
