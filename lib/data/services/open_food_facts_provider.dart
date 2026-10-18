import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'open_food_facts_service.dart';

/// The Open Food Facts client. Tests override it with a fake.
final openFoodFactsServiceProvider = Provider<OpenFoodFactsService>(
  (ref) => HttpOpenFoodFactsService(),
);
