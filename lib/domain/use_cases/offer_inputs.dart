import '../models/place.dart';
import '../models/price_entry.dart';
import '../models/product.dart';
import 'best_offer_scorer.dart';

/// Wraps a price entry with the place location and variant size the scorer needs.
OfferInput offerInputFor(PriceEntry entry, {Variant? variant, Place? place}) {
  final unit = variant?.sizeUnit;
  return OfferInput(
    entry: entry,
    placeLat: place?.lat,
    placeLng: place?.lng,
    baseQuantity: variant?.baseQuantity,
    dimension: unit?.dimension,
  );
}
