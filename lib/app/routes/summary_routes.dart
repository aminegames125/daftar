import 'package:go_router/go_router.dart';

import '../../ui/features/accounts/summary/views/summary_screen.dart';

/// Paths of the account summaries.
abstract final class SummaryRoutes {
  /// Day / week / month / year summary. Open with `context.push(...)`.
  static const summary = '/summary';
}

/// Full-screen routes of the summaries.
final List<RouteBase> summaryRoutes = [
  GoRoute(
    path: SummaryRoutes.summary,
    builder: (_, _) => const SummaryScreen(),
  ),
];
