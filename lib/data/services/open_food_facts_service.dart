import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/models/product.dart';

// Open Food Facts asks every app to send a User-Agent with a
// contact. This is a placeholder: put your real e-mail here before the first
// release (it is only sent in the User-Agent header, nowhere else).
const String kOffContactEmail = 'CHANGE-ME@example.com';

/// "Daftar/0.1.0 (Android; personal price notebook; contact: CHANGE-ME@example.com)".
const String kOffUserAgent =
    'Daftar/0.1.0 (Android; personal price notebook; contact: $kOffContactEmail)';

const String kOffHost = 'world.openfoodfacts.org';

/// Only these fields are requested, to keep the answer small on mobile data.
const String kOffFields =
    'code,product_name,product_name_en,product_name_fr,brands,quantity,image_front_url,image_front_small_url';

const Duration kOffTimeout = Duration(seconds: 8);

/// What Open Food Facts knows about a barcode.
class OffProduct {
  const OffProduct({
    required this.barcode,
    required this.name,
    this.brand,
    this.imageUrl,
    this.quantityText,
    this.sizeValue,
    this.sizeUnit,
  });

  final String barcode;
  final String name;

  /// First brand when several are listed.
  final String? brand;
  final String? imageUrl;

  /// The raw "quantity" text ("100 g", "6 x 33 cl").
  final String? quantityText;

  /// [quantityText] understood as a size, when it could be.
  final double? sizeValue;
  final SizeUnit? sizeUnit;
}

/// Outcome of a lookup. Offline or failing servers are *not* errors for the app:
/// the user simply types the product in.
sealed class OffResult {
  const OffResult();
}

class OffFound extends OffResult {
  const OffFound(this.product);
  final OffProduct product;
}

/// The server answered: this barcode is not in the database.
class OffNotFound extends OffResult {
  const OffNotFound();
}

/// No network, timeout, or a server error. Fall back to manual entry.
class OffUnavailable extends OffResult {
  const OffUnavailable(this.reason);
  final String reason;
}

abstract interface class OpenFoodFactsService {
  Future<OffResult> lookup(String barcode);

  /// Downloads a product picture; null when offline or it fails.
  Future<Uint8List?> downloadImage(String url);
}

class HttpOpenFoodFactsService implements OpenFoodFactsService {
  HttpOpenFoodFactsService({
    http.Client? client,
    this.userAgent = kOffUserAgent,
    this.timeout = kOffTimeout,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;
  final Duration timeout;

  Map<String, String> get _headers => {
    'User-Agent': userAgent,
    'Accept': 'application/json',
  };

  @override
  Future<OffResult> lookup(String barcode) async {
    final code = barcode.trim();
    if (!RegExp(r'^\d{6,14}$').hasMatch(code)) return const OffNotFound();
    final uri = Uri.https(kOffHost, '/api/v2/product/$code.json', {
      'fields': kOffFields,
    });
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout);
      if (response.statusCode == 404) return const OffNotFound();
      if (response.statusCode != 200) {
        return OffUnavailable('HTTP ${response.statusCode}');
      }
      final product = parseOffResponse(
        utf8.decode(response.bodyBytes),
        fallbackBarcode: code,
      );
      return product == null ? const OffNotFound() : OffFound(product);
    } on TimeoutException {
      return const OffUnavailable('timeout');
    } on FormatException {
      return const OffUnavailable('bad answer');
    } on http.ClientException catch (e) {
      return OffUnavailable(e.message);
    } on Exception catch (e) {
      // SocketException (offline) and friends.
      return OffUnavailable(e.toString());
    }
  }

  @override
  Future<Uint8List?> downloadImage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': userAgent})
          .timeout(timeout);
      return response.statusCode == 200 ? response.bodyBytes : null;
    } on Exception {
      return null;
    }
  }
}

/// Reads the Open Food Facts v2 JSON. Returns null when the product is missing
/// or has no usable name.
OffProduct? parseOffResponse(String body, {required String fallbackBarcode}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return null;
  if (decoded['status'] == 0) return null;
  final product = decoded['product'];
  if (product is! Map<String, dynamic>) return null;

  String? text(String key) {
    final value = product[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  final name =
      text('product_name') ??
      text('product_name_en') ??
      text('product_name_fr');
  if (name == null) return null;

  final brands = text('brands');
  final brand = brands
      ?.split(',')
      .map((b) => b.trim())
      .where((b) => b.isNotEmpty)
      .firstOrNull;
  final quantity = text('quantity');
  final size = quantity == null ? null : parseOffQuantity(quantity);

  return OffProduct(
    barcode: text('code') ?? fallbackBarcode,
    name: name,
    brand: brand,
    imageUrl: text('image_front_url') ?? text('image_front_small_url'),
    quantityText: quantity,
    sizeValue: size?.value,
    sizeUnit: size?.unit,
  );
}

final _multiPack = RegExp(
  r'(\d+)\s*[x×*]\s*(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|dl|l)\b',
  caseSensitive: false,
);
final _single = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|dl|l)\b',
  caseSensitive: false,
);

/// Understands "100 g", "1.5 L", "33 cl", "6 x 33 cl" as a size in our units
/// (g, kg, ml, l). Returns null for anything else ("1 piece", "large").
({double value, SizeUnit unit})? parseOffQuantity(String text) {
  final multi = _multiPack.firstMatch(text);
  final single = multi ?? _single.firstMatch(text);
  if (single == null) return null;

  final count = multi == null ? 1 : int.parse(multi.group(1)!);
  final amountGroup = multi == null ? 1 : 2;
  final unitGroup = multi == null ? 2 : 3;
  final amount =
      double.parse(single.group(amountGroup)!.replaceAll(',', '.')) * count;

  return switch (single.group(unitGroup)!.toLowerCase()) {
    'g' => (value: amount, unit: SizeUnit.g),
    'kg' => (value: amount, unit: SizeUnit.kg),
    'ml' => (value: amount, unit: SizeUnit.ml),
    'l' => (value: amount, unit: SizeUnit.l),
    'cl' => (value: amount * 10, unit: SizeUnit.ml),
    'dl' => (value: amount * 100, unit: SizeUnit.ml),
    _ => null,
  };
}
