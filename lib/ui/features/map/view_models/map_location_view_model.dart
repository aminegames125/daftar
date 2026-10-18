import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/geocoding_location.dart';
import '../../places/view_models/place_form_view_model.dart'
    show locationFailureText;

/// Where the phone is, for "locate me" on the maps.
class MapLocationState {
  const MapLocationState({
    this.lat,
    this.lng,
    this.locating = false,
    this.message,
    this.ticket = 0,
  });

  final double? lat;
  final double? lng;

  /// True while waiting for GPS (the radar shows, motion).
  final bool locating;

  /// Why locating failed, in plain words.
  final String? message;

  /// Increases on every successful fix so the map knows to fly there.
  final int ticket;

  bool get hasPosition => lat != null && lng != null;
}

class MapLocationNotifier extends Notifier<MapLocationState> {
  @override
  MapLocationState build() => const MapLocationState();

  /// Gets one GPS fix. Safe to call repeatedly; ignored while already locating.
  Future<LocationFix> locate() async {
    if (state.locating) return const LocationFix.failure(LocationStatus.failed);
    state = MapLocationState(
      lat: state.lat,
      lng: state.lng,
      locating: true,
      ticket: state.ticket,
    );
    final fix = await ref.read(locationServiceProvider).currentPosition();
    if (!ref.mounted) return fix;
    state = fix.isOk
        ? MapLocationState(lat: fix.lat, lng: fix.lng, ticket: state.ticket + 1)
        : MapLocationState(
            lat: state.lat,
            lng: state.lng,
            message: locationFailureText(fix.status),
            ticket: state.ticket,
          );
    return fix;
  }

  void clearMessage() => state = MapLocationState(
    lat: state.lat,
    lng: state.lng,
    ticket: state.ticket,
  );
}

final mapLocationProvider =
    NotifierProvider<MapLocationNotifier, MapLocationState>(
      MapLocationNotifier.new,
    );
