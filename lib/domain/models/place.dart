typedef TimeRange = ({String open, String close});

/// Weekly opening hours. Keys are `mon`…`sun`. A missing day means unknown, an
/// empty list means closed (DATA_MODEL § 5).
class OpeningHours {
  const OpeningHours(this.days);

  final Map<String, List<TimeRange>> days;

  factory OpeningHours.fromJson(Map<String, dynamic> json) => OpeningHours({
    for (final MapEntry(:key, :value) in json.entries)
      key: [
        for (final range in value as List<dynamic>)
          (
            open: (range as List<dynamic>)[0] as String,
            close: range[1] as String,
          ),
      ],
  });

  Map<String, dynamic> toJson() => {
    for (final MapEntry(:key, :value) in days.entries)
      key: [
        for (final range in value) [range.open, range.close],
      ],
  };
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.typeId,
    this.lat,
    this.lng,
    this.address,
    this.phone,
    this.openingHours,
    this.wifiName,
    this.wifiPassword,
    this.rating,
    this.notes,
    this.paymentMethodIds = const [],
    this.tags = const [],
  });

  final String id;
  final String name;
  final String typeId;
  final double? lat;
  final double? lng;
  final String? address;
  final String? phone;
  final OpeningHours? openingHours;
  final String? wifiName;
  final String? wifiPassword;

  /// 1–5, or null when not rated yet.
  final int? rating;
  final String? notes;
  final List<String> paymentMethodIds;

  /// Quick tags: "Clean", "Cheap", "Quiet", …
  final List<String> tags;

  /// Location is optional (online shops).
  bool get hasLocation => lat != null && lng != null;
}
