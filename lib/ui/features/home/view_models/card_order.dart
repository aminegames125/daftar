import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/settings.dart';
import '../../../../data/data_providers.dart';

/// The cards of the home wallet. Declaration order = default order, front first.
enum HomeCardId {
  prices,
  places,
  menus,
  calculator,
  accounts;

  /// Cards shown but not usable yet. None now; kept for cards of later phases.
  bool get isSoon => false;
}

/// Parses the saved order ("prices,menus,…"). Unknown names are dropped, missing
/// cards are appended in default order, so new cards in future updates appear.
List<HomeCardId> parseCardOrder(String? saved) {
  final byName = HomeCardId.values.asNameMap();
  final result = <HomeCardId>[];
  for (final name in (saved ?? '').split(',')) {
    final card = byName[name.trim()];
    if (card != null && !result.contains(card)) result.add(card);
  }
  for (final card in HomeCardId.values) {
    if (!result.contains(card)) result.add(card);
  }
  return result;
}

String serializeCardOrder(List<HomeCardId> order) =>
    order.map((c) => c.name).join(',');

/// Order of the wallet cards (front first), saved in the `settings` table.
final homeCardOrderProvider =
    NotifierProvider<HomeCardOrderController, List<HomeCardId>>(
      HomeCardOrderController.new,
    );

class HomeCardOrderController extends Notifier<List<HomeCardId>> {
  @override
  List<HomeCardId> build() {
    _load();
    return HomeCardId.values;
  }

  Future<void> _load() async {
    try {
      final saved = await ref
          .read(settingsRepositoryProvider)
          .get(AppSettingKeys.homeCardOrder);
      if (saved != null && ref.mounted) state = parseCardOrder(saved);
    } catch (_) {
      // No database available: keep the default order.
    }
  }

  /// Moves the card at [oldIndex] to [newIndex] (final position, as given by
  /// `ReorderableListView.onReorderItem`).
  Future<void> move(int oldIndex, int newIndex) {
    final next = [...state];
    next.insert(newIndex, next.removeAt(oldIndex));
    state = next;
    return ref
        .read(settingsRepositoryProvider)
        .set(AppSettingKeys.homeCardOrder, serializeCardOrder(next));
  }
}
