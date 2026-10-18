import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:daftar/data/services/open_food_facts_service.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _found = {
  'code': '6191234567890',
  'status': 1,
  'status_verbose': 'product found',
  'product': {
    'code': '6191234567890',
    'product_name': 'Milka Oreo',
    'brands': 'Milka, Mondelez',
    'quantity': '100 g',
    'image_front_url': 'https://images.openfoodfacts.org/front.jpg',
  },
};

HttpOpenFoodFactsService serviceFor(
  Future<http.Response> Function(http.Request) handler,
) => HttpOpenFoodFactsService(client: MockClient(handler));

http.Response json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('lookup', () {
    test(
      'sends the v2 URL with a descriptive User-Agent and returns the product',
      () async {
        late http.Request seen;
        final service = serviceFor((request) async {
          seen = request;
          return json(_found);
        });

        final result = await service.lookup('6191234567890');

        expect(seen.url.host, 'world.openfoodfacts.org');
        expect(seen.url.path, '/api/v2/product/6191234567890.json');
        expect(seen.headers['User-Agent'], kOffUserAgent);
        expect(kOffUserAgent, contains('Daftar'));
        expect(kOffUserAgent, contains('contact:'));

        final product = (result as OffFound).product;
        expect(product.name, 'Milka Oreo');
        expect(product.brand, 'Milka');
        expect(product.barcode, '6191234567890');
        expect(product.imageUrl, 'https://images.openfoodfacts.org/front.jpg');
        expect(product.sizeValue, 100);
        expect(product.sizeUnit, SizeUnit.g);
      },
    );

    test('status 0 or HTTP 404 is "not found"', () async {
      final status0 = serviceFor(
        (_) async => json({
          'code': '1',
          'status': 0,
          'status_verbose': 'product not found',
        }),
      );
      expect(await status0.lookup('6191234567890'), isA<OffNotFound>());

      final http404 = serviceFor((_) async => json({'status': 0}, 404));
      expect(await http404.lookup('6191234567890'), isA<OffNotFound>());
    });

    test('a product without a name is "not found"', () async {
      final service = serviceFor(
        (_) async => json({
          'status': 1,
          'product': {'brands': 'X'},
        }),
      );
      expect(await service.lookup('6191234567890'), isA<OffNotFound>());
    });

    test('offline (socket error) is "unavailable", not an exception', () async {
      final service = serviceFor(
        (_) async => throw const SocketException('no route'),
      );
      expect(await service.lookup('6191234567890'), isA<OffUnavailable>());
    });

    test('a timeout is "unavailable"', () async {
      final service = HttpOpenFoodFactsService(
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );
      final result = await service.lookup('6191234567890');
      expect((result as OffUnavailable).reason, 'timeout');
    });

    test('a server error or garbage is "unavailable"', () async {
      expect(
        await serviceFor((_) async => json({}, 503)).lookup('6191234567890'),
        isA<OffUnavailable>(),
      );
      expect(
        await serviceFor((_) async => http.Response('<html>', 200))
            .lookup('6191234567890'),
        isA<OffUnavailable>(),
      );
    });

    test('rubbish barcodes never hit the network', () async {
      var calls = 0;
      final service = serviceFor((_) async {
        calls++;
        return json(_found);
      });
      expect(await service.lookup('abc'), isA<OffNotFound>());
      expect(await service.lookup(''), isA<OffNotFound>());
      expect(calls, 0);
    });
  });

  group('downloadImage', () {
    test('returns the bytes, or null on failure', () async {
      final ok = serviceFor((_) async => http.Response.bytes([1, 2, 3], 200));
      expect(await ok.downloadImage('https://images.openfoodfacts.org/a.jpg'), [
        1,
        2,
        3,
      ]);

      final fail = serviceFor(
        (_) async => throw const SocketException('offline'),
      );
      expect(
        await fail.downloadImage('https://images.openfoodfacts.org/a.jpg'),
        isNull,
      );

      final notFound = serviceFor((_) async => http.Response('', 404));
      expect(
        await notFound.downloadImage('https://images.openfoodfacts.org/a.jpg'),
        isNull,
      );
      expect(await ok.downloadImage('not a url'), isNull);
    });
  });

  group('parseOffQuantity', () {
    test('understands common sizes', () {
      expect(parseOffQuantity('100 g'), (value: 100.0, unit: SizeUnit.g));
      expect(parseOffQuantity('1,5 L'), (value: 1.5, unit: SizeUnit.l));
      expect(parseOffQuantity('1 kg'), (value: 1.0, unit: SizeUnit.kg));
      expect(parseOffQuantity('500ml'), (value: 500.0, unit: SizeUnit.ml));
    });

    test('converts cl and dl to ml and multiplies packs', () {
      expect(parseOffQuantity('33 cl'), (value: 330.0, unit: SizeUnit.ml));
      expect(parseOffQuantity('6 x 33 cl'), (value: 1980.0, unit: SizeUnit.ml));
      expect(parseOffQuantity('4 × 125 g'), (value: 500.0, unit: SizeUnit.g));
    });

    test('gives up on text it does not understand', () {
      expect(parseOffQuantity('1 piece'), isNull);
      expect(parseOffQuantity('large'), isNull);
    });
  });

  group('parseOffResponse', () {
    test('falls back to the French / English name and the small picture', () {
      final product = parseOffResponse(
        jsonEncode({
          'status': 1,
          'product': {
            'product_name': '',
            'product_name_fr': 'Lait demi-écrémé',
            'image_front_small_url': 'https://x/s.jpg',
          },
        }),
        fallbackBarcode: '123456789',
      )!;
      expect(product.name, 'Lait demi-écrémé');
      expect(product.imageUrl, 'https://x/s.jpg');
      expect(product.barcode, '123456789');
      expect(product.brand, isNull);
    });
  });
}
