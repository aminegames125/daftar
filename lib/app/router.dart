import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/models/money.dart';
import '../ui/core/widgets/daftar_nav_bar.dart';
import '../ui/features/calculator/views/calculator_screen.dart';
import '../ui/features/home/views/home_screen.dart';
import '../ui/features/map/views/map_screen.dart';
import '../ui/features/quick_add/views/quick_add_sheet.dart';
import '../ui/features/search/views/search_screen.dart';
import 'routes/accounts_routes.dart';
import 'routes/bills_routes.dart';
import 'routes/core_routes.dart';
import 'routes/debts_routes.dart';
import 'routes/lists_routes.dart';
import 'routes/places_routes.dart';
import 'routes/prices_routes.dart';
import 'routes/rates_routes.dart';
import 'routes/summary_routes.dart';
import 'routes/transfers_routes.dart';

/// Every route path in the app. Paths are declared here up front so features can
/// link to each other before the target screen exists; each track registers the
/// builders for its own paths in `routes/<track>_routes.dart`.
///
/// Query parameters (all optional): `placeId`, `productId`, `variantId`.
abstract final class Routes {
  // Main tabs (shell).
  static const home = '/home';
  static const search = '/search';
  static const map = '/map';
  static const calculator = '/calculator';

  /// Full-screen calculator that pops the chosen amount as a `Money` (or null).
  /// Use `pickFromCalculator(context)` rather than pushing this directly.
  static const calculatorPick = '/calculator/pick';

  // Saved shopping lists (reached from the Calculator).
  static const lists = '/lists';
  static String listDetail(String id) => '/lists/$id';

  // Core / settings
  static const settings = '/settings';

  // Places & menus
  static const places = '/places';
  static const placeNew = '/places/new';

  /// The new-place form, filled from text shared out of Google Maps.
  static String placeNewFrom(String text) =>
      '/places/new?import=${Uri.encodeQueryComponent(text)}';
  static String placeDetail(String id) => '/places/$id';
  static String placeEdit(String id) => '/places/$id/edit';

  /// Snap a menu photo (OCR) → review. `?placeId=` optional; asks for a place when missing.
  static const menuSnap = '/menu/snap';

  // Prices & products
  /// "Log a price". Prefill with `?placeId=`, `?variantId=`, `?productId=`.
  static const logPrice = '/prices/new';
  static const products = '/products';
  static String productDetail(String id) => '/products/$id';

  // Bills & subscriptions.
  static const bills = '/bills';
  static const billNew = '/bills/new';
  static String billDetail(String id) => '/bills/$id';
  static String billEdit(String id) => '/bills/$id/edit';

  /// Barcode scanner. Pops with the scanned code, or opens the product / "new product" flow.
  static const scan = '/scan';
}

/// Opens the calculator to pick an amount; resolves to the inserted amount, or
/// null when the user backs out.
Future<Money?> pickFromCalculator(BuildContext context) =>
    context.push<Money>(Routes.calculatorPick);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.search,
                builder: (_, _) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.map, builder: (_, _) => const MapScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.calculator,
                builder: (_, _) => const CalculatorScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen routes (no floating nav): each track owns its own list.
      GoRoute(
        path: Routes.calculatorPick,
        builder: (_, _) => const CalculatorScreen(pick: true),
      ),
      ...listsRoutes,
      ...coreRoutes,
      ...accountsRoutes,
      ...placesRoutes,
      ...pricesRoutes,
      ...ratesRoutes,
      ...transfersRoutes,
      ...debtsRoutes,
      ...summaryRoutes,
      ...billsRoutes,
    ],
  );
});

/// Main tabs: a Material 3 navigation bar, with the lime "+" floating just
/// above it. The body ends above the bar; scrolling content pads its bottom by
/// Chrome.contentBottomPadding so the last item clears the "+".
class _MainShell extends StatelessWidget {
  const _MainShell({required this.shell});

  final StatefulNavigationShell shell;

  static const _destinations = [
    NavDestination(icon: Icons.home_rounded, label: 'Home'),
    NavDestination(icon: Icons.search_rounded, label: 'Search'),
    NavDestination(icon: Icons.map_outlined, label: 'Map'),
    NavDestination(icon: Icons.calculate_outlined, label: 'Calculator'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DaftarNavBar(
        onAdd: () => showQuickAddSheet(context),
        destinations: _destinations,
        currentIndex: shell.currentIndex,
        onSelect: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}
