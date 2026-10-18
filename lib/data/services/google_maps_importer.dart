import 'package:http/http.dart' as http;

import '../../domain/place_logic/google_maps_link.dart';

/// Turns what Google Maps shares (a link, share text, or "lat, lng") into a
/// [GoogleMapsPlace]. Short `maps.app.goo.gl` links are followed once over the
/// network to find the real place address. No key and no Google account needed.
class GoogleMapsImporter {
  GoogleMapsImporter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Returns null when nothing usable is found or the network is down.
  Future<GoogleMapsPlace?> import(String text) async {
    final direct = parseGoogleMapsText(text);
    if (direct != null && direct.hasPosition) return direct;

    final link = findLink(text);
    if (link == null) return direct;
    if (!isShortMapsLink(link)) return direct;

    try {
      final response = await _client
          .get(
            Uri.parse(link),
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Daftar',
            },
          )
          .timeout(const Duration(seconds: 10));
      final finalUrl = response.request?.url.toString();
      final fromUrl = finalUrl == null ? null : parseGoogleMapsText(finalUrl);
      final place = fromUrl ?? parseGoogleMapsText(response.body);
      if (place == null) return direct;
      // Keep the name from the share text when the final address has none.
      return GoogleMapsPlace(
        name: place.name ?? direct?.name ?? _nameFromShareText(text),
        lat: place.lat,
        lng: place.lng,
      );
    } on Object {
      return direct;
    }
  }

  /// "Café Nour\nhttps://maps.app.goo.gl/abc": the first line before the link.
  static String? _nameFromShareText(String text) {
    final link = findLink(text);
    if (link == null) return null;
    final before = text.substring(0, text.indexOf(link)).trim();
    if (before.isEmpty) return null;
    return before.split('\n').first.trim();
  }

  void dispose() => _client.close();
}
