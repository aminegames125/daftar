import '../models/place.dart';

/// Quick tags offered on the place form. The user can add their own.
const quickTags = [
  'Clean',
  'Cheap',
  'Quiet',
  'Good Wi-Fi',
  'Slow service',
  'Friendly',
  'Fresh',
  'Crowded',
  'Expensive',
];

enum PlaceDraftError { nameRequired, typeRequired, ratingOutOfRange }

/// Editable copy of a [Place] while the form is open. Pure data + validation.
class PlaceDraft {
  const PlaceDraft({
    required this.id,
    this.name = '',
    this.typeId,
    this.lat,
    this.lng,
    this.address = '',
    this.phone = '',
    this.openingHours,
    this.wifiName = '',
    this.wifiPassword = '',
    this.paymentMethodIds = const {},
    this.rating,
    this.tags = const [],
    this.notes = '',
  });

  factory PlaceDraft.fromPlace(Place p) => PlaceDraft(
    id: p.id,
    name: p.name,
    typeId: p.typeId,
    lat: p.lat,
    lng: p.lng,
    address: p.address ?? '',
    phone: p.phone ?? '',
    openingHours: p.openingHours,
    wifiName: p.wifiName ?? '',
    wifiPassword: p.wifiPassword ?? '',
    paymentMethodIds: p.paymentMethodIds.toSet(),
    rating: p.rating,
    tags: [...p.tags],
    notes: p.notes ?? '',
  );

  final String id;
  final String name;
  final String? typeId;
  final double? lat;
  final double? lng;
  final String address;
  final String phone;
  final OpeningHours? openingHours;
  final String wifiName;
  final String wifiPassword;
  final Set<String> paymentMethodIds;
  final int? rating;
  final List<String> tags;
  final String notes;

  bool get hasLocation => lat != null && lng != null;

  /// Copy with changes. Nullable fields have a `clear…` flag because `null`
  /// means "keep" for a plain argument.
  PlaceDraft copyWith({
    String? name,
    String? typeId,
    double? lat,
    double? lng,
    bool clearLocation = false,
    String? address,
    String? phone,
    OpeningHours? openingHours,
    bool clearHours = false,
    String? wifiName,
    String? wifiPassword,
    Set<String>? paymentMethodIds,
    int? rating,
    bool clearRating = false,
    List<String>? tags,
    String? notes,
  }) => PlaceDraft(
    id: id,
    name: name ?? this.name,
    typeId: typeId ?? this.typeId,
    lat: clearLocation ? null : (lat ?? this.lat),
    lng: clearLocation ? null : (lng ?? this.lng),
    address: address ?? this.address,
    phone: phone ?? this.phone,
    openingHours: clearHours ? null : (openingHours ?? this.openingHours),
    wifiName: wifiName ?? this.wifiName,
    wifiPassword: wifiPassword ?? this.wifiPassword,
    paymentMethodIds: paymentMethodIds ?? this.paymentMethodIds,
    rating: clearRating ? null : (rating ?? this.rating),
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
  );

  Set<PlaceDraftError> validate() => {
    if (name.trim().isEmpty) PlaceDraftError.nameRequired,
    if (typeId == null) PlaceDraftError.typeRequired,
    if (rating != null && (rating! < 1 || rating! > 5))
      PlaceDraftError.ratingOutOfRange,
  };

  bool get isValid => validate().isEmpty;

  /// The domain place, with blanks turned into nulls. Throws if invalid.
  Place toPlace() {
    final errors = validate();
    if (errors.isNotEmpty) throw StateError('Invalid place draft: $errors');
    String? blank(String s) => s.trim().isEmpty ? null : s.trim();
    final hours = openingHours;
    return Place(
      id: id,
      name: name.trim(),
      typeId: typeId!,
      lat: lat,
      lng: lng,
      address: blank(address),
      phone: blank(phone),
      openingHours: hours == null || hours.days.isEmpty ? null : hours,
      wifiName: blank(wifiName),
      // The password keeps its spaces: they can be part of it.
      wifiPassword: wifiPassword.isEmpty ? null : wifiPassword,
      rating: rating,
      notes: blank(notes),
      paymentMethodIds: paymentMethodIds.toList(),
      tags: tags
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList(),
    );
  }
}

/// Keeps digits, `+`, spaces and separators; drops letters and other junk.
String cleanPhone(String raw) =>
    raw.replaceAll(RegExp(r'[^0-9+\s().\-]'), '').trim();

/// What `tel:` needs: digits and a leading `+` only.
String dialablePhone(String raw) {
  final plus = raw.trim().startsWith('+') ? '+' : '';
  return plus + raw.replaceAll(RegExp(r'[^0-9]'), '');
}
