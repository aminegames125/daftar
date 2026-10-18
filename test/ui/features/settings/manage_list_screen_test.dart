import 'dart:async';

import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/ui/features/settings/view_models/managed_lists.dart';
import 'package:daftar/ui/features/settings/views/manage_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/test_app.dart';

/// A [ManagedList] in memory, so the screen can be tested without a database.
class FakeManagedList implements ManagedList {
  FakeManagedList(this.kind, this._items);

  @override
  final ManagedListKind kind;
  final List<ManagedItem> _items;
  final StreamController<List<ManagedItem>> _changes =
      StreamController.broadcast();
  final List<ManagedItem> hidden = [];
  int restoreCalls = 0;
  PlaceKind? lastAddedKind;

  void _emit() => _changes.add(List.of(_items));

  @override
  Stream<List<ManagedItem>> watch() async* {
    yield List.of(_items);
    yield* _changes.stream;
  }

  @override
  Future<void> add(String name, {PlaceKind placeKind = PlaceKind.shop}) async {
    lastAddedKind = placeKind;
    _items.add(
      ManagedItem(id: 'new-${_items.length}', name: name, isBuiltIn: false),
    );
    _emit();
  }

  @override
  Future<void> rename(ManagedItem item, String name) async {
    final i = _items.indexWhere((e) => e.id == item.id);
    _items[i] = ManagedItem(
      id: item.id,
      name: name,
      isBuiltIn: item.isBuiltIn,
      iconKey: item.iconKey,
    );
    _emit();
  }

  @override
  Future<void> hide(ManagedItem item) async {
    hidden.add(item);
    _items.removeWhere((e) => e.id == item.id);
    _emit();
  }

  @override
  Future<void> reorder(List<ManagedItem> ordered) async {
    _items
      ..clear()
      ..addAll(ordered);
    _emit();
  }

  @override
  Future<int> restoreStarters(List<ManagedItem> current) async {
    restoreCalls++;
    return 0;
  }

  @override
  int get starterCount => 3;
}

void main() {
  late FakeManagedList fake;

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<ManagedItem>? items,
    ManagedListKind kind = ManagedListKind.categories,
    bool dark = true,
  }) async {
    fake = FakeManagedList(
      kind,
      List.of(
        items ??
            const [
              ManagedItem(
                id: 'a',
                name: 'Food',
                isBuiltIn: true,
                iconKey: 'restaurant',
              ),
              ManagedItem(
                id: 'b',
                name: 'Drinks',
                isBuiltIn: true,
                iconKey: 'local_drink',
              ),
              ManagedItem(id: 'c', name: 'My stuff', isBuiltIn: false),
            ],
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ManageListScreen(kind: kind),
        ),
      ],
    );
    await tester.pumpWidget(
      testRouterApp(
        router,
        dark: dark,
        overrides: [managedListProvider(kind).overrideWithValue(fake)],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the rows, marking starters', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('My stuff'), findsOneWidget);
    expect(find.text('Starter'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('light theme builds', (tester) async {
    await pumpScreen(tester, dark: false);
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('tap a row to rename it (starter rows too)', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Groceries');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
  });

  testWidgets(
    'Add opens a sheet and appends the new row; empty names are ignored',
    (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add a category'),
        findsOneWidget,
      ); // still open: nothing typed

      await tester.enterText(find.byType(TextField), 'سلع منزلية');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('سلع منزلية'), findsOneWidget);
    },
  );

  testWidgets('place types ask whether the place has products or a menu', (
    tester,
  ) async {
    await pumpScreen(tester, kind: ManagedListKind.placeTypes);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Barber');
    await tester.tap(find.text('A menu (venue)'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fake.lastAddedKind, PlaceKind.venue);
  });

  testWidgets('hiding needs a full hold; a short press does nothing', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Hide Drinks'));
    await tester.pumpAndSettle();
    expect(find.text('Hide "Drinks"?'), findsOneWidget);

    final button = tester.getCenter(find.text('Hold to hide'));
    final short = await tester.startGesture(button);
    await tester.pump(const Duration(milliseconds: 300));
    await short.up();
    await tester.pumpAndSettle();
    expect(fake.hidden, isEmpty);

    final long = await tester.startGesture(button);
    await tester.pump(const Duration(milliseconds: 150)); // press registers
    await tester.pump(const Duration(milliseconds: 1000));
    await long.up();
    await tester.pumpAndSettle();
    expect(fake.hidden.map((e) => e.id), ['b']);
    expect(find.text('Drinks'), findsNothing);
  });

  testWidgets('cancel keeps the row', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Hide My stuff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.hidden, isEmpty);
    expect(find.text('My stuff'), findsOneWidget);
  });

  testWidgets(
    'Restore starters is wired and tells the user when nothing came back',
    (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Restore starters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fake.restoreCalls, 1);
      expect(find.text('Nothing to restore'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    },
  );

  testWidgets('when everything is hidden an empty state offers to restore', (
    tester,
  ) async {
    await pumpScreen(tester, items: []);
    expect(find.text('Everything here is hidden.'), findsOneWidget);
    await tester.tap(find.text('Restore starters'));
    await tester.pump();
    expect(fake.restoreCalls, 1);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });
}
