import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/categories_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/lookups.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/products/views/manage_categories_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const existing = [
    Category(id: 'a', name: 'Café', iconKey: 'x', sortOrder: 1),
    Category(id: 'b', name: 'Dairy', iconKey: 'x', sortOrder: 5),
  ];

  group('categoryNameError', () {
    test('rejects empty and duplicate names, ignoring case and accents', () {
      expect(categoryNameError('  ', existing), isNotNull);
      expect(categoryNameError('cafe', existing), isNotNull);
      expect(categoryNameError('Snacks', existing), isNull);
    });

    test('allows keeping the name of the category being renamed', () {
      expect(categoryNameError('Café', existing, exceptId: 'a'), isNull);
      expect(categoryNameError('Dairy', existing, exceptId: 'a'), isNotNull);
    });
  });

  test('newCategory goes after the last one and is not built-in', () {
    final c = newCategory('  Pets ', existing);
    expect(c.name, 'Pets');
    expect(c.sortOrder, 6);
    expect(c.isBuiltIn, isFalse);
    expect(c.iconKey, kCustomCategoryIcon);
  });

  testWidgets('adds, renames and hides a category', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftCategoriesRepository(db);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: ManageCategoriesSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = (await tester.runAsync(() => repo.watchAll().first))!.length;

    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pets');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    var all = (await tester.runAsync(() => repo.watchAll().first))!;
    expect(all.length, before + 1);
    expect(all.last.name, 'Pets');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Pets'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pets'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pet food');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    all = (await tester.runAsync(() => repo.watchAll().first))!;
    expect(all.map((c) => c.name), contains('Pet food'));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Hide Pet food'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('Hide Pet food'));
    await tester.pumpAndSettle();
    all = (await tester.runAsync(() => repo.watchAll().first))!;
    expect(all.length, before);
  });
}
