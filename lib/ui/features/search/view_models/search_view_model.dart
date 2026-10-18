import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/map_pin.dart';
import '../../prices/view_models/user_location.dart';
import '../../products/view_models/catalog_providers.dart';
import 'search_engine.dart';

/// Wait this long after the last key before searching.
const Duration kSearchDebounce = Duration(milliseconds: 220);

enum SearchMode { list, map }

enum SearchStatus { idle, searching, done, failed }

/// Which kinds of result are shown.
enum SearchFilter {
  all('All'),
  products('Products'),
  menus('Menu items'),
  places('Places');

  const SearchFilter(this.label);
  final String label;
}

/// Settings key holding the recent searches (a JSON list of strings).
const String kRecentSearchesKey = 'recent_searches';
const int kMaxRecentSearches = 8;

/// [results] narrowed to one [filter].
SearchResults applySearchFilter(SearchResults results, SearchFilter filter) =>
    switch (filter) {
      SearchFilter.all => results,
      SearchFilter.products => SearchResults(
        query: results.query,
        priced: results.priced.whereType<ProductPriced>().toList(),
      ),
      SearchFilter.menus => SearchResults(
        query: results.query,
        priced: results.priced.whereType<MenuPriced>().toList(),
      ),
      SearchFilter.places => SearchResults(
        query: results.query,
        places: results.places,
      ),
    };

class SearchState {
  const SearchState({
    this.query = '',
    this.mode = SearchMode.list,
    this.status = SearchStatus.idle,
    this.results = SearchResults.none,
    this.selected = 0,
    this.optionGroup = 0,
    this.now,
    this.filter = SearchFilter.all,
    this.recents = const [],
  });

  final String query;
  final SearchMode mode;
  final SearchStatus status;
  final SearchResults results;

  /// Which priced hit is shown as the Best option card (index into `results.priced`).
  final int selected;

  /// Which option label (S / L) of a selected menu hit is compared.
  final int optionGroup;

  /// The clock the results were scored at (for "3 days ago" labels).
  final DateTime? now;
  final SearchFilter filter;

  /// Latest finished searches, newest first.
  final List<String> recents;

  /// [results] after the [filter]; everything the screen shows comes from here.
  SearchResults get shown => applySearchFilter(results, filter);

  PricedHit? get active =>
      selected < shown.priced.length ? shown.priced[selected] : null;

  /// Pins for the Map segment: the active hit's priced places, or the matching
  /// places when nothing priced matched.
  List<MapPin> get pins {
    switch (active) {
      case ProductPriced(:final hit):
        return pinsForOffers(hit.offers);
      case MenuPriced(:final hit):
        if (hit.groups.isEmpty) return const [];
        return pinsForOffers(
          hit.groups[optionGroup.clamp(0, hit.groups.length - 1)].offers,
        );
      case null:
        return pinsForPlaces(shown.places);
    }
  }

  SearchState copyWith({
    String? query,
    SearchMode? mode,
    SearchStatus? status,
    SearchResults? results,
    int? selected,
    int? optionGroup,
    DateTime? now,
    SearchFilter? filter,
    List<String>? recents,
  }) => SearchState(
    query: query ?? this.query,
    mode: mode ?? this.mode,
    status: status ?? this.status,
    results: results ?? this.results,
    selected: selected ?? this.selected,
    optionGroup: optionGroup ?? this.optionGroup,
    now: now ?? this.now,
    filter: filter ?? this.filter,
    recents: recents ?? this.recents,
  );
}

/// Debounce override point for tests.
final searchDebounceProvider = Provider<Duration>((ref) => kSearchDebounce);

final searchEngineProvider = Provider<SearchEngine>(
  (ref) => SearchEngine(
    products: ref.watch(productsRepositoryProvider),
    places: ref.watch(placesRepositoryProvider),
    menu: ref.watch(menuRepositoryProvider),
    prices: ref.watch(pricesRepositoryProvider),
    globalTypes: ref.watch(globalPriceTypesRepositoryProvider),
  ),
);

final searchViewModelProvider = NotifierProvider<SearchViewModel, SearchState>(
  SearchViewModel.new,
);

class SearchViewModel extends Notifier<SearchState> {
  Timer? _debounce;
  int _request = 0;

  @override
  SearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    ref.read(userLocationProvider); // start locating early
    unawaited(_loadRecents());
    return const SearchState();
  }

  /// The user typed. An empty box clears the results at once.
  void setQuery(String text) {
    _debounce?.cancel();
    _request++;
    if (text.trim().isEmpty) {
      state = SearchState(
        mode: state.mode,
        filter: state.filter,
        recents: state.recents,
      );
      return;
    }
    state = state.copyWith(query: text, status: SearchStatus.searching);
    _debounce = Timer(ref.read(searchDebounceProvider), () => _run(text));
  }

  Future<void> _run(String text) async {
    final request = ++_request;
    try {
      final now = ref.read(clockProvider)();
      final staleDays = await ref
          .read(settingsRepositoryProvider)
          .getStaleDays();
      // Distance is a bonus: never make the search wait long for the GPS.
      final from = await ref
          .read(userLocationProvider.future)
          .timeout(const Duration(milliseconds: 400), onTimeout: () => null);
      final results = await ref
          .read(searchEngineProvider)
          .search(text, now: now, staleDays: staleDays, from: from);
      if (!ref.mounted || request != _request) return;
      state = SearchState(
        query: text,
        mode: state.mode,
        status: SearchStatus.done,
        results: results,
        now: now,
        filter: state.filter,
        recents: state.recents,
      );
    } on Object {
      if (ref.mounted && request == _request) {
        state = state.copyWith(status: SearchStatus.failed);
      }
    }
  }

  Future<void> _loadRecents() async {
    try {
      final raw = await ref
          .read(settingsRepositoryProvider)
          .get(kRecentSearchesKey);
      if (raw == null || !ref.mounted) return;
      final list = [for (final e in jsonDecode(raw) as List) e.toString()];
      state = state.copyWith(recents: list);
    } on Object {
      // Recents are a convenience; ignore a bad value.
    }
  }

  Future<void> _saveRecents(List<String> recents) async {
    state = state.copyWith(recents: recents);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .set(kRecentSearchesKey, jsonEncode(recents));
    } on Object {
      // Not persisted this time; still shown for the session.
    }
  }

  /// Remember the current query (called when the user opens a result).
  Future<void> remember([String? text]) async {
    final q = (text ?? state.query).trim();
    if (q.isEmpty) return;
    final key = q.toLowerCase();
    final next = [q, ...state.recents.where((r) => r.toLowerCase() != key)];
    await _saveRecents(next.take(kMaxRecentSearches).toList());
  }

  Future<void> clearRecents() => _saveRecents(const []);

  Future<void> removeRecent(String text) =>
      _saveRecents([...state.recents.where((r) => r != text)]);

  void setFilter(SearchFilter filter) =>
      state = state.copyWith(filter: filter, selected: 0, optionGroup: 0);

  void setMode(SearchMode mode) => state = state.copyWith(mode: mode);

  /// Show another priced hit as the Best option.
  void select(int index) =>
      state = state.copyWith(selected: index, optionGroup: 0);

  void selectOptionGroup(int index) =>
      state = state.copyWith(optionGroup: index);
}
