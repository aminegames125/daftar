import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Runs tasks one at a time with at least [minInterval] between their starts.
/// Nominatim's usage policy allows 1 request per second at most.
class RateLimiter {
  RateLimiter({
    this.minInterval = const Duration(seconds: 1),
    DateTime Function()? now,
    Future<void> Function(Duration)? wait,
  }) : _now = now ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed;

  final Duration minInterval;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;

  Future<void> _tail = Future<void>.value();
  DateTime? _lastStart;

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) async {
      final last = _lastStart;
      if (last != null) {
        final remaining = minInterval - _now().difference(last);
        if (remaining > Duration.zero) await _wait(remaining);
      }
      _lastStart = _now();
      return task();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// One address-search hit.
class GeocodeResult {
  const GeocodeResult({
    required this.displayName,
    required this.lat,
    required this.lng,
    this.name,
  });

  /// Full line, e.g. "Café Yasmine, Rue de Marseille, Tunis, Tunisia".
  final String displayName;

  /// Short name of the thing itself when Nominatim has one ("Café Yasmine").
  final String? name;
  final double lat;
  final double lng;

  /// [name], or the first comma-separated part of [displayName].
  String get title => (name != null && name!.isNotEmpty)
      ? name!
      : displayName.split(',').first.trim();
}

class NominatimException implements Exception {
  const NominatimException(this.message);
  final String message;
  @override
  String toString() => 'NominatimException: $message';
}

/// Address search over OpenStreetMap's Nominatim. Everything here is optional
/// and must fail soft: callers show "Can't search right now" and keep working.
class NominatimClient {
  NominatimClient({
    http.Client? client,
    RateLimiter? rateLimiter,
    this.userAgent = defaultUserAgent,
    this.countryCodes = 'tn',
    this.baseUrl = 'https://nominatim.openstreetmap.org',
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _limiter = rateLimiter ?? RateLimiter();

  // Nominatim requires an identifying User-Agent. This uses the
  // app id; add a contact e-mail if you want one.
  static const defaultUserAgent =
      'Daftar/0.1 (personal price notebook, Android, com.amineos.daftar)';

  final http.Client _client;
  final RateLimiter _limiter;
  final String userAgent;

  /// Comma-separated ISO country codes to bias results (null = worldwide).
  // defaults to Tunisia only; pass null for worldwide.
  final String? countryCodes;
  final String baseUrl;
  final Duration timeout;

  final _cache = <String, List<GeocodeResult>>{};

  Map<String, String> get _headers => {
    'User-Agent': userAgent,
    'Accept': 'application/json',
  };

  /// Searches [query]. Blank queries return an empty list without a request.
  /// Throws [NominatimException] when the network or the server fails.
  Future<List<GeocodeResult>> search(String query, {int limit = 5}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final key = '$q|$limit';
    final cached = _cache[key];
    if (cached != null) return cached;

    final uri = Uri.parse('$baseUrl/search').replace(
      queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'limit': '$limit',
        'addressdetails': '0',
        'countrycodes': ?countryCodes,
      },
    );
    final body = await _get(uri);
    final results = [
      for (final item in (body as List<dynamic>))
        ?_parse(item as Map<String, dynamic>),
    ];
    return _cache[key] = results;
  }

  /// Address for a pin position, or null when there is none.
  Future<String?> reverse(double lat, double lng) async {
    final uri = Uri.parse('$baseUrl/reverse').replace(
      queryParameters: {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'jsonv2',
        'zoom': '18',
      },
    );
    final body = await _get(uri);
    if (body is Map<String, dynamic>) return body['display_name'] as String?;
    return null;
  }

  Future<Object?> _get(Uri uri) {
    return _limiter.run(() async {
      try {
        final response = await _client
            .get(uri, headers: _headers)
            .timeout(timeout);
        if (response.statusCode != 200) {
          throw NominatimException('HTTP ${response.statusCode}');
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on NominatimException {
        rethrow;
      } on TimeoutException {
        throw const NominatimException('Timed out');
      } on FormatException {
        throw const NominatimException('Unreadable answer');
      } catch (e) {
        // SocketException, ClientException, ...: treat all as "no network".
        throw NominatimException('No connection ($e)');
      }
    });
  }

  GeocodeResult? _parse(Map<String, dynamic> json) {
    final lat = double.tryParse('${json['lat']}');
    final lng = double.tryParse('${json['lon']}');
    final display = json['display_name'] as String?;
    if (lat == null || lng == null || display == null) return null;
    return GeocodeResult(
      displayName: display,
      lat: lat,
      lng: lng,
      name: json['name'] as String?,
    );
  }

  void close() => _client.close();
}
