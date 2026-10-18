import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/models/place.dart';
import '../../../../domain/place_logic/place_draft.dart';
import '../../products/view_models/directions.dart';

/// Opens the phone dialer with the place's number (`tel:`). False when the place
/// has no number or nothing can handle it.
Future<bool> callPlace(Place place) async {
  final phone = place.phone;
  if (phone == null || phone.trim().isEmpty) return false;
  return _launch(Uri(scheme: 'tel', path: dialablePhone(phone)));
}

/// Opens Google Maps with directions to the place. False without a location.
Future<bool> directionsToPlace(Place place) => openDirections(place);

Future<bool> _launch(Uri uri) async {
  try {
    return await launchUrl(uri);
  } on Object {
    return false;
  }
}
