import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'google_maps_importer.dart';
import 'nominatim_client.dart';

enum LocationStatus {
  ok,
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  failed,
}

class LocationFix {
  const LocationFix.ok(double this.lat, double this.lng, {this.accuracyMeters})
    : status = LocationStatus.ok;
  const LocationFix.failure(this.status)
    : lat = null,
      lng = null,
      accuracyMeters = null;

  final LocationStatus status;
  final double? lat;
  final double? lng;
  final double? accuracyMeters;

  bool get isOk => status == LocationStatus.ok;
}

abstract interface class LocationService {
  /// One GPS fix ("I'm here"). Asks for permission when needed. Never throws.
  Future<LocationFix> currentPosition();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationFix> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationFix.failure(LocationStatus.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationFix.failure(
          LocationStatus.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const LocationFix.failure(LocationStatus.permissionDenied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationFix.ok(
        position.latitude,
        position.longitude,
        accuracyMeters: position.accuracy,
      );
    } catch (_) {
      return const LocationFix.failure(LocationStatus.failed);
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);

final nominatimClientProvider = Provider<NominatimClient>((ref) {
  final client = NominatimClient();
  ref.onDispose(client.close);
  return client;
});

final googleMapsImporterProvider = Provider<GoogleMapsImporter>((ref) {
  final importer = GoogleMapsImporter();
  ref.onDispose(importer.dispose);
  return importer;
});
