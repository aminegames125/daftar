import 'dart:convert';

import 'package:daftar/data/services/nominatim_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RateLimiter', () {
    test('waits so that two tasks start at least minInterval apart', () async {
      var clock = DateTime(2026);
      final waits = <Duration>[];
      final limiter = RateLimiter(
        now: () => clock,
        wait: (d) async {
          waits.add(d);
          clock = clock.add(d);
        },
      );
      await limiter.run(() async => 1);
      clock = clock.add(const Duration(milliseconds: 300));
      await limiter.run(() async => 2);
      expect(waits, [const Duration(milliseconds: 700)]);
      clock = clock.add(const Duration(seconds: 5));
      await limiter.run(() async => 3);
      expect(waits.length, 1);
    });

    test(
      'runs concurrent tasks one after another and survives failures',
      () async {
        final limiter = RateLimiter(minInterval: Duration.zero);
        final order = <int>[];
        final a = limiter.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          order.add(1);
          throw StateError('boom');
        });
        final b = limiter.run(() async => order.add(2));
        await expectLater(a, throwsStateError);
        await b;
        expect(order, [1, 2]);
      },
    );
  });

  group('NominatimClient', () {
    NominatimClient make(
      MockClientHandler handler, {
      String? countryCodes = 'tn',
    }) => NominatimClient(
      client: MockClient(handler),
      rateLimiter: RateLimiter(minInterval: Duration.zero),
      countryCodes: countryCodes,
    );

    test('sends a descriptive User-Agent and parses results', () async {
      late http.Request seen;
      final client = make((request) async {
        seen = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'lat': '36.8',
                'lon': '10.18',
                'display_name': 'Café Yasmine, Tunis, Tunisia',
                'name': 'Café Yasmine',
              },
              {'lat': 'x', 'lon': '1', 'display_name': 'bad'},
            ]),
          ),
          200,
        );
      });
      final results = await client.search('  café yasmine ');
      expect(seen.headers['User-Agent'], startsWith('Daftar/'));
      expect(seen.url.queryParameters['q'], 'café yasmine');
      expect(seen.url.queryParameters['countrycodes'], 'tn');
      expect(seen.url.queryParameters['format'], 'jsonv2');
      expect(results, hasLength(1));
      expect(results.single.title, 'Café Yasmine');
      expect(results.single.lat, 36.8);
      expect(results.single.lng, 10.18);
    });

    test(
      'worldwide when countryCodes is null; blank query makes no request',
      () async {
        var calls = 0;
        final client = make((request) async {
          calls++;
          expect(
            request.url.queryParameters.containsKey('countrycodes'),
            isFalse,
          );
          return http.Response('[]', 200);
        }, countryCodes: null);
        expect(await client.search('   '), isEmpty);
        expect(calls, 0);
        await client.search('tunis');
        expect(calls, 1);
      },
    );

    test('caches identical queries', () async {
      var calls = 0;
      final client = make((_) async {
        calls++;
        return http.Response('[]', 200);
      });
      await client.search('tunis');
      await client.search('tunis');
      expect(calls, 1);
    });

    test('reverse returns display_name', () async {
      final client = make((request) async {
        expect(request.url.path, '/reverse');
        return http.Response(jsonEncode({'display_name': 'Rue X, Tunis'}), 200);
      });
      expect(await client.reverse(36.8, 10.18), 'Rue X, Tunis');
    });

    test('maps HTTP, parse and network errors to NominatimException', () async {
      await expectLater(
        make((_) async => http.Response('no', 503)).search('a'),
        throwsA(isA<NominatimException>()),
      );
      await expectLater(
        make((_) async => http.Response('<html>', 200)).search('b'),
        throwsA(isA<NominatimException>()),
      );
      await expectLater(
        make((_) async => throw http.ClientException('offline')).search('c'),
        throwsA(isA<NominatimException>()),
      );
    });
  });
}
