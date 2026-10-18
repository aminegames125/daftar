import 'money.dart';

/// One logged price. Every entry is kept so history and charts work.
///
/// Exactly one of [variantId] / [menuOptionId] is set. A null [placeId] means a
/// global price, which then needs a [globalTypeId].
class PriceEntry {
  PriceEntry({
    required this.id,
    this.variantId,
    this.menuOptionId,
    this.placeId,
    this.globalTypeId,
    required this.amount,
    this.amountMax,
    required this.seenAt,
    this.isPromo = false,
    this.promoEndsAt,
    this.note,
  }) : assert(
         (variantId == null) != (menuOptionId == null),
         'Set exactly one of variantId / menuOptionId',
       ),
       assert(
         placeId != null || globalTypeId != null,
         'A global price needs a type',
       ),
       assert(amountMax == null || amountMax.currency == amount.currency),
       assert(amountMax == null || amountMax.minor >= amount.minor);

  final String id;
  final String? variantId;
  final String? menuOptionId;
  final String? placeId;
  final String? globalTypeId;

  /// The price, or the minimum when [amountMax] is set. Scoring uses this value.
  final Money amount;

  /// Upper end of a min–max range ("6.000–8.000"), if any.
  final Money? amountMax;
  final DateTime seenAt;
  final bool isPromo;
  final DateTime? promoEndsAt;
  final String? note;

  bool get isGlobal => placeId == null;

  /// A promo whose end date has passed no longer counts.
  bool isExpiredAt(DateTime now) =>
      isPromo && promoEndsAt != null && promoEndsAt!.isBefore(now);
}
