import 'package:go_router/go_router.dart';

import '../../ui/features/calculator/views/saved_list_detail_screen.dart';
import '../../ui/features/calculator/views/saved_lists_screen.dart';
import '../router.dart';

/// Full-screen routes of the saved shopping lists (reached from the Calculator).
final List<RouteBase> listsRoutes = [
  GoRoute(path: Routes.lists, builder: (_, _) => const SavedListsScreen()),
  GoRoute(
    path: '/lists/:id',
    builder: (_, state) =>
        SavedListDetailScreen(listId: state.pathParameters['id']!),
  ),
];
