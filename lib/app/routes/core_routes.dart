import 'package:go_router/go_router.dart';

import '../../ui/features/lock/views/pin_flow_screen.dart';
import '../../ui/features/settings/view_models/managed_lists.dart';
import '../../ui/features/settings/views/manage_list_screen.dart';
import '../../ui/features/settings/views/settings_screen.dart';
import '../router.dart';

/// Sub-pages of Settings (the root page is `Routes.settings`).
abstract final class SettingsRoutes {
  /// Add / rename / reorder / hide the rows of one editable list.
  static String manage(ManagedListKind kind) =>
      '${Routes.settings}/lists/${kind.name}';

  /// PIN prompt. Pops with the entered PIN (or null). `create` asks twice,
  /// `verify` checks the current PIN.
  static String pin(PinFlowMode mode) => '${Routes.settings}/pin/${mode.name}';
}

/// Full-screen routes for settings and the app lock.
final List<RouteBase> coreRoutes = [
  GoRoute(
    path: Routes.settings,
    builder: (_, _) => const SettingsScreen(),
    routes: [
      GoRoute(
        path: 'lists/:kind',
        builder: (_, state) => ManageListScreen(
          kind:
              ManagedListKind.values
                  .asNameMap()[state.pathParameters['kind']] ??
              ManagedListKind.placeTypes,
        ),
      ),
      GoRoute(
        path: 'pin/:mode',
        builder: (_, state) => PinFlowScreen(
          mode:
              PinFlowMode.values.asNameMap()[state.pathParameters['mode']] ??
              PinFlowMode.verify,
        ),
      ),
    ],
  ),
];
