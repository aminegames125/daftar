/// One pin on the map. Produced by search/price code, drawn by the map
/// widget. This model is the contract between them.
class MapPin {
  const MapPin({
    required this.placeId,
    required this.lat,
    required this.lng,
    required this.label,
    this.isBest = false,
    this.isStale = false,
    this.isPromo = false,
  });

  final String placeId;
  final double lat;
  final double lng;

  /// Text on the pin: a formatted price ("4.400"), or a place name for plain place pins.
  final String label;

  /// The best option: lime glow.
  final bool isBest;

  /// Older than the stale threshold: faded.
  final bool isStale;

  /// Promo: amber outline.
  final bool isPromo;
}
