import 'package:go_router/go_router.dart';

import '../../ui/features/accounts/transfers/views/exchange_detail_screen.dart';
import '../../ui/features/accounts/transfers/views/exchange_log_screen.dart';

/// Paths of the transfer / exchange screens. The two sheets are opened with
/// `showTransferSheet(context, accountId: ...)` and `showExchangeSheet(context, ...)`
/// (ui/features/accounts/transfers/views/), not by route.
abstract final class TransfersRoutes {
  /// All exchanges, newest first.
  static const exchangeLog = '/accounts/exchanges';

  /// One exchange (both legs share [pairId]); has the hold-to-delete.
  static String exchangeDetail(String pairId) => '/accounts/exchanges/$pairId';
}

final List<RouteBase> transfersRoutes = [
  GoRoute(
    path: TransfersRoutes.exchangeLog,
    builder: (_, _) => const ExchangeLogScreen(),
  ),
  GoRoute(
    path: '${TransfersRoutes.exchangeLog}/:pairId',
    builder: (_, state) =>
        ExchangeDetailScreen(pairId: state.pathParameters['pairId']!),
  ),
];
