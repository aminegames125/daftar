import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/map_pin.dart';

/// Price pins to show on the Map tab, set by search before it sends the
/// user to the map. `null` means plain places only.
///
/// ```dart
/// ref.read(mapPricePinsProvider.notifier).show(pins);
/// context.go(Routes.map);
/// ```
class MapPricePinsNotifier extends Notifier<List<MapPin>?> {
  @override
  List<MapPin>? build() => null;

  void show(List<MapPin> pins) => state = pins;

  void clear() => state = null;
}

final mapPricePinsProvider =
    NotifierProvider<MapPricePinsNotifier, List<MapPin>?>(
      MapPricePinsNotifier.new,
    );
