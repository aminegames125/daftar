import 'package:daftar/domain/place_logic/google_maps_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the pin, not the map centre, from a full place link', () {
    final p = parseGoogleMapsText(
      'https://www.google.com/maps/place/Caf%C3%A9+Nour/@36.80,10.18,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d36.8065!4d10.1815',
    )!;
    expect(p.name, 'Café Nour');
    expect(p.lat, 36.8065);
    expect(p.lng, 10.1815);
  });

  test('falls back to @lat,lng', () {
    final p = parseGoogleMapsText(
      'https://www.google.com/maps/@36.8,10.18,15z',
    )!;
    expect([p.lat, p.lng], [36.8, 10.18]);
  });

  test('reads ?q=lat,lng, geo: links and plain coordinates', () {
    expect(
      parseGoogleMapsText('https://maps.google.com/?q=36.8,10.2')!.lat,
      36.8,
    );
    expect(parseGoogleMapsText('geo:36.8,10.2?q=x')!.lng, 10.2);
    expect(parseGoogleMapsText('36.8065, 10.1815')!.lng, 10.1815);
  });

  test('finds the link inside Google Maps share text', () {
    const share =
        'Café Nour\nhttps://www.google.com/maps/place/Cafe/@36.8,10.18,17z';
    expect(
      findLink(share),
      startsWith('https://www.google.com/maps/place/Cafe'),
    );
    expect(parseGoogleMapsText(share)!.lat, 36.8);
  });

  test('short links need the network; junk gives nothing', () {
    expect(isShortMapsLink('https://maps.app.goo.gl/abc'), isTrue);
    expect(parseGoogleMapsText('https://maps.app.goo.gl/abc'), isNull);
    expect(parseGoogleMapsText('hello'), isNull);
    expect(parseGoogleMapsText('999, 999'), isNull);
  });
}
