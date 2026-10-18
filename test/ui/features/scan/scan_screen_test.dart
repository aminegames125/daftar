import 'dart:typed_data';

import 'package:daftar/data/repositories/products_repository.dart';
import 'package:daftar/data/services/open_food_facts_service.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/scan/view_models/barcode_lookup.dart';
import 'package:daftar/ui/features/scan/views/barcode_laser.dart';
import 'package:daftar/ui/features/scan/views/camera_scanner_view.dart';
import 'package:daftar/ui/features/scan/views/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Products implements ProductsRepository {
  @override
  Future<Product?> findByBarcode(String barcode) async => barcode == '111111'
      ? const Product(
          id: 'm',
          name: 'Milka',
          variants: [
            Variant(id: 'v', productId: 'm', name: 'Oreo', barcode: '111111'),
          ],
        )
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Off implements OpenFoodFactsService {
  _Off(this.result);
  final OffResult result;

  @override
  Future<OffResult> lookup(String barcode) async => result;

  @override
  Future<Uint8List?> downloadImage(String url) async => null;
}

Widget app({
  required bool pick,
  OffResult off = const OffUnavailable('x'),
  ValueChanged<String?>? onPopped,
  ScannerProblem? problem,
}) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await context.push<String>('/scan');
              onPopped?.call(result);
            },
            child: const Text('open-scan'),
          ),
        ),
      ),
      GoRoute(
        path: '/scan',
        builder: (_, _) => ScanScreen(pickMode: pick),
      ),
      GoRoute(
        path: '/prices/new',
        builder: (_, s) => Scaffold(body: Text('LOG ${s.uri.query}')),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      barcodeLookupProvider.overrideWithValue(
        BarcodeLookup(_Products(), _Off(off)),
      ),
      scannerViewBuilderProvider.overrideWithValue((
        context,
        onCode,
        torch,
        onProblem,
      ) {
        if (problem != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => onProblem(problem),
          );
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => onCode('111111'),
                child: const Text('emit-local'),
              ),
              TextButton(
                onPressed: () => onCode('222222'),
                child: const Text('emit-unknown'),
              ),
            ],
          ),
        );
      }),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true, size: Size(390, 844)),
      child: MaterialApp.router(routerConfig: router, theme: AppTheme.dark()),
    ),
  );
}

void main() {
  testWidgets('pick mode pops with the scanned code', (tester) async {
    String? popped;
    await tester.pumpWidget(app(pick: true, onPopped: (v) => popped = v));
    await tester.tap(find.text('open-scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('emit-unknown'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(popped, '222222');
  });

  testWidgets('a known barcode offers View prices and Log price', (
    tester,
  ) async {
    await tester.pumpWidget(app(pick: false));
    await tester.tap(find.text('open-scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('emit-local'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Milka'), findsOneWidget);
    expect(find.text('View prices'), findsOneWidget);
    await tester.tap(find.text('Log price'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('productId=m'), findsOneWidget);
  });

  testWidgets('an unknown barcode while offline falls back to typing', (
    tester,
  ) async {
    await tester.pumpWidget(app(pick: false));
    await tester.tap(find.text('open-scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('emit-unknown'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('offline'), findsOneWidget);
    await tester.tap(find.text('Log price'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('barcode=222222'), findsOneWidget);
  });

  testWidgets('an Open Food Facts hit shows its name', (tester) async {
    await tester.pumpWidget(
      app(
        pick: false,
        off: const OffFound(
          OffProduct(
            barcode: '222222',
            name: 'Water',
            brand: 'Safia',
            quantityText: '1.5 L',
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('emit-unknown'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Water'), findsOneWidget);
    expect(find.textContaining('Open Food Facts'), findsOneWidget);
  });

  testWidgets(
    'camera permission denied shows a clear empty state and manual entry still works',
    (tester) async {
      await tester.pumpWidget(
        app(pick: false, problem: ScannerProblem.permissionDenied),
      );
      await tester.tap(find.text('open-scan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Camera access is off'), findsOneWidget);
      expect(find.textContaining('Permissions'), findsOneWidget);
      expect(find.byType(BarcodeLaser), findsNothing);
      expect(find.byTooltip('Turn the light on'), findsNothing);

      await tester.tap(find.text('Type the code'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), '333333');
      await tester.tap(find.text('Use code'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('333333'), findsOneWidget);
      expect(find.text('New barcode'), findsOneWidget);
    },
  );

  testWidgets('an unavailable camera has its own message', (tester) async {
    await tester.pumpWidget(
      app(pick: false, problem: ScannerProblem.unavailable),
    );
    await tester.tap(find.text('open-scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('The camera is not available'), findsOneWidget);
  });

  testWidgets('pick mode: a typed code pops with it', (tester) async {
    String? popped;
    await tester.pumpWidget(app(pick: true, onPopped: (v) => popped = v));
    await tester.tap(find.text('open-scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Type the code'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), ' 444444 ');
    await tester.tap(find.text('Use code'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(popped, '444444');
  });

  testWidgets('an Open Food Facts hit leads to Log price with the barcode', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        pick: false,
        off: const OffFound(OffProduct(barcode: '222222', name: 'Water')),
      ),
    );
    await tester.tap(find.text('open-scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('emit-unknown'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Log price'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('barcode=222222'), findsOneWidget);
  });
}
