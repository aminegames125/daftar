import 'package:go_router/go_router.dart';

import '../../ui/features/accounts/rates/rates_screen.dart';
import '../../ui/features/accounts/rates/reverse_calculator_screen.dart';

/// Paths of the USD rate screens. Push them with `context.push(...)`.
abstract final class RatesRoutes {
  /// Rate history chart and the list of saved rates.
  static const rates = '/rates';

  /// "I need 500 TND, how many USD?"
  static const reverse = '/rates/reverse';
}

/// Full-screen routes of the foreign-currency flow.
final List<RouteBase> ratesRoutes = [
  GoRoute(path: RatesRoutes.rates, builder: (_, _) => const RatesScreen()),
  GoRoute(
    path: RatesRoutes.reverse,
    builder: (_, _) => const ReverseCalculatorScreen(),
  ),
];
