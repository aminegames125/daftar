enum PhotoOwner { place, product, price, menu }

/// A photo stored as a file in the app documents directory (`photos/<uuid>.jpg`).
class Photo {
  const Photo({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.filePath,
    this.ocrText,
  });

  final String id;
  final PhotoOwner ownerType;
  final String ownerId;
  final String filePath;

  /// Text ML Kit read from a menu photo, kept for reference.
  final String? ocrText;
}
