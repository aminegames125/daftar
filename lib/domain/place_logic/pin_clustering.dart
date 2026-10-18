import 'dart:math' as math;

/// A group of nearby items drawn as one marker. A cluster with one member is
/// just that item.
class Cluster<T> {
  const Cluster({required this.members, required this.lat, required this.lng});

  final List<T> members;

  /// Centroid of the members (the member itself for a single one).
  final double lat;
  final double lng;

  bool get isSingle => members.length == 1;
  T get first => members.first;
}

/// World pixel position of a point at [zoom] on the 256 px Web Mercator grid.
({double x, double y}) projectToWorldPixels(
  double lat,
  double lng,
  double zoom,
) {
  final scale = 256 * math.pow(2, zoom).toDouble();
  final clampedLat = lat.clamp(-85.0511, 85.0511);
  final sinLat = math.sin(clampedLat * math.pi / 180);
  final x = (lng + 180) / 360 * scale;
  final y =
      (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
  return (x: x, y: y);
}

/// Simple grid clustering: items whose screen position at [zoom]
/// falls in the same [cellPx] x [cellPx] cell are merged. At or above
/// [maxClusterZoom] nothing is merged. Order of clusters follows first
/// appearance of each cell, so results are stable.
List<Cluster<T>> clusterByGrid<T>(
  Iterable<T> items, {
  required double Function(T) lat,
  required double Function(T) lng,
  required double zoom,
  double cellPx = 64,
  double maxClusterZoom = 17,
}) {
  final list = items.toList();
  if (zoom >= maxClusterZoom) {
    return [
      for (final i in list) Cluster(members: [i], lat: lat(i), lng: lng(i)),
    ];
  }
  final cells = <(int, int), List<T>>{};
  for (final item in list) {
    final p = projectToWorldPixels(lat(item), lng(item), zoom);
    cells
        .putIfAbsent(((p.x / cellPx).floor(), (p.y / cellPx).floor()), () => [])
        .add(item);
  }
  return [
    for (final members in cells.values)
      Cluster(
        members: members,
        lat: members.map(lat).reduce((a, b) => a + b) / members.length,
        lng: members.map(lng).reduce((a, b) => a + b) / members.length,
      ),
  ];
}
