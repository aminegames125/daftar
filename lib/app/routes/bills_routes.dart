import 'package:go_router/go_router.dart';

import '../../ui/features/bills/views/bill_detail_screen.dart';
import '../../ui/features/bills/views/bill_form_screen.dart';
import '../../ui/features/bills/views/bills_screen.dart';
import '../router.dart';

/// Full-screen routes of bills & subscriptions.
///
/// `/bills/new` must come before `/bills/:id` so "new" is not read as an id.
final List<RouteBase> billsRoutes = [
  GoRoute(path: Routes.bills, builder: (_, _) => const BillsScreen()),
  GoRoute(path: Routes.billNew, builder: (_, _) => const BillFormScreen()),
  GoRoute(
    path: '/bills/:id/edit',
    builder: (_, state) => BillFormScreen(billId: state.pathParameters['id']),
  ),
  GoRoute(
    path: '/bills/:id',
    builder: (_, state) =>
        BillDetailScreen(billId: state.pathParameters['id']!),
  ),
];
