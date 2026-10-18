import 'package:daftar/domain/place_logic/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('haversine: Tunis to Sfax is about 235 km', () {
    expect(haversineKm(36.8065, 10.1815, 34.7406, 10.7603), closeTo(235, 6));
  });

  test('haversine: same point is 0', () {
    expect(haversineKm(36.8, 10.1, 36.8, 10.1), 0);
  });

  test('formatDistanceKm', () {
    expect(formatDistanceKm(0.347), '350 m');
    expect(formatDistanceKm(1.23), '1.2 km');
    expect(formatDistanceKm(14.4), '14 km');
  });
}
