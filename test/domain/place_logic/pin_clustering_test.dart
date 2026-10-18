import 'package:daftar/domain/place_logic/pin_clustering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = (lat: 36.8000, lng: 10.1800);
  const nearA = (lat: 36.8001, lng: 10.1801);
  const far = (lat: 34.74, lng: 10.76);

  List<Cluster<({double lat, double lng})>> run(
    List<({double lat, double lng})> pts,
    double zoom,
  ) => clusterByGrid(pts, lat: (p) => p.lat, lng: (p) => p.lng, zoom: zoom);

  test('nearby points merge at low zoom, far points stay apart', () {
    final clusters = run([a, nearA, far], 10);
    expect(clusters, hasLength(2));
    final merged = clusters.firstWhere((c) => c.members.length == 2);
    expect(merged.lat, closeTo(36.80005, 1e-9));
    expect(merged.isSingle, isFalse);
    expect(clusters.firstWhere((c) => c.isSingle).first, far);
  });

  test('zooming in splits them again', () {
    expect(run([a, nearA], 10), hasLength(1));
    expect(run([a, nearA], 17), hasLength(2));
  });

  test('cluster count never increases when zooming in', () {
    final pts = [
      a,
      nearA,
      far,
      (lat: 36.81, lng: 10.19),
      (lat: 36.9, lng: 10.3),
    ];
    var previous = 0;
    for (var z = 4.0; z <= 18; z++) {
      final n = run(pts, z).length;
      expect(n, greaterThanOrEqualTo(previous));
      previous = n;
    }
    expect(previous, pts.length);
  });

  test('empty input and every item is kept exactly once', () {
    expect(run([], 8), isEmpty);
    final pts = [a, nearA, far];
    expect(run(pts, 8).expand((c) => c.members).length, 3);
  });

  test('projectToWorldPixels: origin and symmetry', () {
    final p = projectToWorldPixels(0, 0, 0);
    expect(p.x, closeTo(128, 1e-6));
    expect(p.y, closeTo(128, 1e-6));
    expect(projectToWorldPixels(0, 0, 1).x, closeTo(256, 1e-6));
  });
}
