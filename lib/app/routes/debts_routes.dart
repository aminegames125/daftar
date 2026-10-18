import 'package:go_router/go_router.dart';

import '../../ui/features/debts/views/debt_detail_screen.dart';
import '../../ui/features/debts/views/debt_form_screen.dart';
import '../../ui/features/debts/views/debts_screen.dart';

/// Paths of the debts feature.
abstract final class DebtsRoutes {
  static const list = '/debts';
  static const add = '/debts/new';
  static String detail(String id) => '/debts/$id';
  static String edit(String id) => '/debts/$id/edit';
}

/// Full-screen routes of Later: Debts & loans. `/debts/new` is declared before
/// `/debts/:id` so "new" is not read as an id.
final List<RouteBase> debtsRoutes = [
  GoRoute(path: DebtsRoutes.list, builder: (_, _) => const DebtsScreen()),
  GoRoute(path: DebtsRoutes.add, builder: (_, _) => const DebtFormScreen()),
  GoRoute(
    path: '/debts/:id/edit',
    builder: (_, state) => DebtFormScreen(debtId: state.pathParameters['id']),
  ),
  GoRoute(
    path: '/debts/:id',
    builder: (_, state) =>
        DebtDetailScreen(debtId: state.pathParameters['id']!),
  ),
];
