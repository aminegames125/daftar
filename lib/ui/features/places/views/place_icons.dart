import 'package:flutter/material.dart';

/// Icon for a place type's `iconKey` (seed keys in `seed_data.dart`; users may
/// add their own types, which fall back to a generic pin).
IconData placeTypeIcon(String key) => switch (key) {
  'shopping_cart' => Icons.shopping_cart_outlined,
  'storefront' => Icons.storefront_outlined,
  'bakery' => Icons.bakery_dining_outlined,
  'pharmacy' => Icons.local_pharmacy_outlined,
  'butcher' => Icons.kebab_dining_outlined,
  'devices' => Icons.devices_outlined,
  'cafe' => Icons.local_cafe_outlined,
  'restaurant' => Icons.restaurant_outlined,
  'fast_food' => Icons.lunch_dining_outlined,
  'content_cut' => Icons.content_cut_rounded,
  'car_wash' => Icons.local_car_wash_outlined,
  'fitness' => Icons.fitness_center_outlined,
  'build' => Icons.build_outlined,
  _ => Icons.place_outlined,
};

/// Icon for a payment method's `iconKey`.
IconData paymentIcon(String key) => switch (key) {
  'payments' => Icons.payments_outlined,
  'credit_card' => Icons.credit_card_outlined,
  'wallet' => Icons.account_balance_wallet_outlined,
  'contactless' => Icons.contactless_outlined,
  'account_balance' => Icons.account_balance_outlined,
  _ => Icons.payment_outlined,
};
