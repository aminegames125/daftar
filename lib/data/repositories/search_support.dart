import 'repository_support.dart';

/// Normalised, non-empty tokens of a user query (see `normalizeForSearch`).
List<String> searchTokens(String query) =>
    searchKeyOf([query]).split(' ').where((t) => t.isNotEmpty).toList();

/// SQL LIKE pattern matching [token] anywhere in a search key. Use with `escapeChar: r'\'`.
String likeContains(String token) =>
    '%${token.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
