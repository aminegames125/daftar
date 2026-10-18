import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../domain/use_cases/best_offer_scorer.dart';

/// Reads the phone's position **without asking for permission**: if location was
/// never granted (or is switched off) the answer is null and the app simply skips
/// distances. Asking happens in the place form's "I'm here" flow, not a side effect of Log price
/// or Search. Never throws.
Future<GeoPoint?> readUserLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }
    final position =
        await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 4),
          ),
        );
    return (lat: position.latitude, lng: position.longitude);
  } on Object {
    return null;
  }
}

/// The user's position or null. Tests override it with a fixed point.
final userLocationProvider = FutureProvider<GeoPoint?>(
  (ref) => readUserLocation(),
);
