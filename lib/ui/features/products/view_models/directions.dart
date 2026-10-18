import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/models/place.dart';

/// The Google Maps "directions" address for [place]. It opens the Google Maps
/// app (with the route to the place ready to start) and falls back to the
/// browser when the app is missing.
Uri googleDirectionsUri(Place place) =>
    Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${place.lat},${place.lng}',
      'travelmode': 'driving',
    });

/// Opens Google Maps with directions to [place]. Falls back to any maps app
/// (`geo:`) when Google Maps and a browser are both missing. False when the
/// place has no location or nothing could open it.
Future<bool> openDirections(Place place) async {
  if (!place.hasLocation) return false;
  try {
    if (await launchUrl(
      googleDirectionsUri(place),
      mode: LaunchMode.externalApplication,
    )) {
      return true;
    }
  } on Object {
    // fall through to geo:
  }
  final label = Uri.encodeComponent(place.name);
  final geo = Uri.parse(
    'geo:${place.lat},${place.lng}?q=${place.lat},${place.lng}($label)',
  );
  try {
    return await launchUrl(geo);
  } on Object {
    return false;
  }
}
