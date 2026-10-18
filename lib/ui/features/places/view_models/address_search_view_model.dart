import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/geocoding_location.dart';
import '../../../../data/services/nominatim_client.dart';

class AddressSearchState {
  const AddressSearchState({
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.offline = false,
  });

  final String query;
  final List<GeocodeResult> results;
  final bool loading;

  /// The last search failed (no network, server busy). The form still works.
  final bool offline;

  bool get hasSearched => query.trim().isNotEmpty && !loading && !offline;
}

/// Address search box state (Nominatim, optional and offline-safe).
class AddressSearchNotifier extends Notifier<AddressSearchState> {
  static const debounce = Duration(milliseconds: 700);

  Timer? _timer;
  var _seq = 0;

  @override
  AddressSearchState build() {
    ref.onDispose(() => _timer?.cancel());
    return const AddressSearchState();
  }

  /// Call on every keystroke; searches after the user pauses.
  void onQueryChanged(String query) {
    _timer?.cancel();
    state = AddressSearchState(
      query: query,
      results: query.trim().isEmpty ? const [] : state.results,
    );
    if (query.trim().length < 3) return;
    _timer = Timer(debounce, () => search(query));
  }

  Future<void> search(String query) async {
    _timer?.cancel();
    final id = ++_seq;
    state = AddressSearchState(
      query: query,
      results: state.results,
      loading: true,
    );
    try {
      final results = await ref.read(nominatimClientProvider).search(query);
      if (!ref.mounted || id != _seq) return;
      state = AddressSearchState(query: query, results: results);
    } on NominatimException {
      if (!ref.mounted || id != _seq) return;
      state = AddressSearchState(query: query, offline: true);
    }
  }

  void clear() {
    _timer?.cancel();
    _seq++;
    state = const AddressSearchState();
  }
}

final addressSearchProvider =
    NotifierProvider.autoDispose<AddressSearchNotifier, AddressSearchState>(
      AddressSearchNotifier.new,
    );
