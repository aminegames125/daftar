/// A place read out of a Google Maps link or share text.
class GoogleMapsPlace {
  const GoogleMapsPlace({this.name, this.lat, this.lng});

  /// The place name when the link carries one (`/maps/place/NAME/`).
  final String? name;
  final double? lat;
  final double? lng;

  bool get hasPosition => lat != null && lng != null;
}

/// Finds the first web address in [text]. Google Maps' "Share" gives
/// "Place name\nhttps://maps.app.goo.gl/abc", so the link is not the whole text.
String? findLink(String text) {
  final m = RegExp(r'https?://[^\s<>"]+').firstMatch(text);
  return m?.group(0);
}

/// True for the short links Google Maps shares; they must be followed to get at
/// the place (see `GoogleMapsImporter`).
bool isShortMapsLink(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host == 'maps.app.goo.gl' ||
      host == 'goo.gl' ||
      host == 'g.co' ||
      host == 'share.google';
}

bool _validLat(double v) => v >= -90 && v <= 90;
bool _validLng(double v) => v >= -180 && v <= 180;

GoogleMapsPlace? _coords(String lat, String lng, String? name) {
  final la = double.tryParse(lat);
  final ln = double.tryParse(lng);
  if (la == null || ln == null || !_validLat(la) || !_validLng(ln)) return null;
  return GoogleMapsPlace(name: name, lat: la, lng: ln);
}

/// Reads a place from a full Google Maps address, a `geo:` link or plain
/// "lat, lng" text. Returns null when there is nothing usable. It does not touch
/// the network: short links are handled by the importer first.
GoogleMapsPlace? parseGoogleMapsText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  // Plain "36.8065, 10.1815".
  final plain = RegExp(
    r'^(-?\d{1,3}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)$',
  ).firstMatch(trimmed);
  if (plain != null) return _coords(plain.group(1)!, plain.group(2)!, null);

  final link =
      findLink(trimmed) ?? (trimmed.startsWith('geo:') ? trimmed : null);
  if (link == null) return null;

  String? name;
  final nameMatch = RegExp(r'/maps/place/([^/@?]+)').firstMatch(link);
  if (nameMatch != null) {
    try {
      name = Uri.decodeComponent(nameMatch.group(1)!.replaceAll('+', ' '))
          .trim();
    } on Object {
      name = null;
    }
    if (name != null && name.isEmpty) name = null;
  }

  // The pin itself: !3d<lat>!4d<lng>. It beats "@", which is only the map centre.
  final pin = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)')
      .firstMatch(link);
  if (pin != null) return _coords(pin.group(1)!, pin.group(2)!, name);

  final at = RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)').firstMatch(link);
  if (at != null) return _coords(at.group(1)!, at.group(2)!, name);

  final q = RegExp(
    r'[?&](?:q|query|ll|destination|center)=(-?\d+(?:\.\d+)?)(?:,|%2C)(-?\d+(?:\.\d+)?)',
  ).firstMatch(link);
  if (q != null) return _coords(q.group(1)!, q.group(2)!, name);

  final geo = RegExp(r'^geo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)')
      .firstMatch(link);
  if (geo != null) return _coords(geo.group(1)!, geo.group(2)!, name);

  // A named place with no coordinates still gives the name.
  return name == null ? null : GoogleMapsPlace(name: name);
}
