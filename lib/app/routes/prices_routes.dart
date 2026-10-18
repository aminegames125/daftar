import 'package:go_router/go_router.dart';

import '../../ui/features/prices/view_models/log_price_view_model.dart';
import '../../ui/features/prices/views/log_price_screen.dart';
import '../../ui/features/products/views/product_detail_screen.dart';
import '../../ui/features/products/views/products_screen.dart';
import '../../ui/features/scan/views/scan_screen.dart';
import '../router.dart';

/// The URL of "Log a price" with optional pre-filled values (`?placeId=`,
/// `?productId=`, `?variantId=`, `?barcode=`). Use with `context.push(...)`.
String logPriceLocation({
  String? placeId,
  String? productId,
  String? variantId,
  String? barcode,
}) {
  final params = {
    'placeId': ?placeId,
    'productId': ?productId,
    'variantId': ?variantId,
    'barcode': ?barcode,
  };
  return Uri(
    path: Routes.logPrice,
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

/// The scanner in "pick" mode: it pops with the scanned code instead of opening
/// a product (used by the barcode button on Log a price).
const String scanPickLocation = '${Routes.scan}?pick=1';

/// Full-screen routes for prices (log price, products, scanner).
final List<RouteBase> pricesRoutes = [
  GoRoute(
    path: Routes.logPrice,
    builder: (_, state) {
      final q = state.uri.queryParameters;
      return LogPriceScreen(
        args: LogPriceArgs(
          placeId: q['placeId'],
          productId: q['productId'],
          variantId: q['variantId'],
          barcode: q['barcode'],
        ),
      );
    },
  ),
  GoRoute(path: Routes.products, builder: (_, _) => const ProductsScreen()),
  GoRoute(
    path: '${Routes.products}/:id',
    builder: (_, state) => ProductDetailScreen(
      productId: state.pathParameters['id']!,
      variantId: state.uri.queryParameters['variantId'],
    ),
  ),
  GoRoute(
    path: Routes.scan,
    builder: (_, state) =>
        ScanScreen(pickMode: state.uri.queryParameters['pick'] == '1'),
  ),
];
