import '../../domain/search/normalize_for_search.dart';

/// Source of "now"; tests inject a fixed clock.
typedef Now = DateTime Function();

int toEpochMs(DateTime time) => time.toUtc().millisecondsSinceEpoch;

DateTime fromEpochMs(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();

/// Search key for a text entity: the normalised name plus other searchable words.
String searchKeyOf(Iterable<String?> parts) =>
    normalizeForSearch(parts.whereType<String>().join(' '));
