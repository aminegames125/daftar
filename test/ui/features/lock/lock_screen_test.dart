import 'package:daftar/ui/features/lock/view_models/lock_controller.dart';
import 'package:daftar/ui/features/lock/views/lock_gate.dart';
import 'package:daftar/ui/features/lock/views/lock_screen.dart';
import 'package:daftar/ui/features/lock/views/pin_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/test_app.dart';

class FakeLock extends LockController {
  FakeLock({
    this.initial = const AppLockState(ready: true, enabled: true, locked: true),
    this.pin = '1234',
  });

  final AppLockState initial;
  final String pin;
  int blocked = 0;
  final List<String> tried = [];

  @override
  AppLockState build() => initial;

  /// Public view of the protected `state`, for assertions.
  AppLockState get current => state;

  @override
  Future<PinCheck> checkPin(String entered) async {
    tried.add(entered);
    if (blocked > 0) return PinCheck.blocked;
    return entered == pin ? PinCheck.ok : PinCheck.wrong;
  }

  @override
  Future<PinCheck> unlockWithPin(String entered) async {
    final result = await checkPin(entered);
    if (result == PinCheck.ok) state = state.copyWith(locked: false);
    return result;
  }

  @override
  Future<bool> biometricAvailable() async => false;

  @override
  int blockedSeconds() => 30;
}

Future<void> tapPin(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  group('LockScreen', () {
    Future<FakeLock> pumpLock(
      WidgetTester tester, {
      bool dark = true,
      bool reduce = true,
    }) async {
      final fake = FakeLock();
      await tester.pumpWidget(
        testApp(
          const LockScreen(),
          dark: dark,
          reduceMotion: reduce,
          overrides: [lockControllerProvider.overrideWith(() => fake)],
        ),
      );
      await tester.pump();
      return fake;
    }

    testWidgets('shows the Dal, the dots and the keypad (dark and light)', (
      tester,
    ) async {
      await pumpLock(tester);
      expect(find.text('Enter your PIN'), findsOneWidget);
      for (final d in '0123456789'.split('')) {
        expect(find.text(d), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Delete'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pumpLock(tester, dark: false);
      expect(find.text('Enter your PIN'), findsOneWidget);
    });

    testWidgets(
      'a wrong pin shows an error, clears the dots and keeps the lock',
      (tester) async {
        final fake = await pumpLock(tester);
        await tapPin(tester, '9999');
        expect(find.text('Wrong PIN'), findsOneWidget);
        expect(fake.current.locked, isTrue);

        // The dots were cleared: a new full entry is evaluated again.
        await tapPin(tester, '1234');
        expect(fake.tried, ['9999', '1234']);
        expect(fake.current.locked, isFalse);
      },
    );

    testWidgets('typing fills dots, delete removes one', (tester) async {
      await pumpLock(tester);
      await tapPin(tester, '12');
      expect(find.bySemanticsLabel('2 of 4 digits entered'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Delete'));
      await tester.pump();
      expect(find.bySemanticsLabel('1 of 4 digits entered'), findsOneWidget);
    });

    testWidgets('too many tries shows the wait message', (tester) async {
      final fake = await pumpLock(tester);
      fake.blocked = 1;
      await tapPin(tester, '1234');
      expect(find.text('Too many tries. Wait 30 s'), findsOneWidget);
      expect(fake.current.locked, isTrue);
    });

    testWidgets('fits a small phone at 130% text', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final fake = FakeLock();
      await tester.pumpWidget(
        testApp(
          const LockScreen(),
          reduceMotion: true,
          textScale: 1.3,
          overrides: [lockControllerProvider.overrideWith(() => fake)],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Dal breathes when animations are on', (tester) async {
      await pumpLock(tester, reduce: false);
      final start = tester.getSize(find.byType(BreathingDal)).width;
      await tester.pump(const Duration(milliseconds: 1600));
      final scale = tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(BreathingDal),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .getMaxScaleOnAxis();
      expect(start, 72);
      expect(scale, greaterThan(1));
    });
  });

  group('LockGate', () {
    Future<FakeLock> pumpGate(WidgetTester tester, AppLockState state) async {
      final fake = FakeLock(initial: state);
      await tester.pumpWidget(
        testApp(
          const LockGate(child: Center(child: Text('secret prices'))),
          reduceMotion: true,
          overrides: [lockControllerProvider.overrideWith(() => fake)],
        ),
      );
      await tester.pump();
      return fake;
    }

    testWidgets('content is hidden until the settings are known', (
      tester,
    ) async {
      await pumpGate(tester, const AppLockState());
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('secret prices').hitTestable(), findsNothing);
      expect(find.text('secret prices', skipOffstage: false), findsOneWidget);
      expect(find.byType(ColoredBox), findsWidgets);
    });

    testWidgets('locked: the lock screen covers the app and blocks touches', (
      tester,
    ) async {
      await pumpGate(
        tester,
        const AppLockState(ready: true, enabled: true, locked: true),
      );
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('secret prices').hitTestable(), findsNothing);
    });

    testWidgets('unlocked or no lock: the app is usable', (tester) async {
      await pumpGate(tester, const AppLockState(ready: true));
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('secret prices').hitTestable(), findsOneWidget);
    });

    testWidgets('entering the pin removes the lock screen', (tester) async {
      await pumpGate(
        tester,
        const AppLockState(ready: true, enabled: true, locked: true),
      );
      await tapPin(tester, '1234');
      await tester.pump();
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('secret prices').hitTestable(), findsOneWidget);
    });
  });

  group('PinFlowScreen', () {
    Future<List<String?>> pumpFlow(
      WidgetTester tester,
      PinFlowMode mode,
      FakeLock fake,
    ) async {
      final results = <String?>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      results.add(await context.push<String>('/pin')),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/pin',
            builder: (_, _) => PinFlowScreen(mode: mode),
          ),
        ],
      );
      await tester.pumpWidget(
        testRouterApp(
          router,
          overrides: [lockControllerProvider.overrideWith(() => fake)],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('create: asks twice and returns the pin', (tester) async {
      final results = await pumpFlow(tester, PinFlowMode.create, FakeLock());
      expect(find.text('Choose a PIN'), findsOneWidget);
      await tapPin(tester, '4821');
      await tester.pumpAndSettle();
      expect(find.text('Repeat your PIN'), findsOneWidget);
      await tapPin(tester, '4821');
      await tester.pumpAndSettle();
      expect(results, ['4821']);
    });

    testWidgets('create: a mismatch starts over with a message', (
      tester,
    ) async {
      final results = await pumpFlow(tester, PinFlowMode.create, FakeLock());
      await tapPin(tester, '4821');
      await tester.pumpAndSettle();
      await tapPin(tester, '1111');
      await tester.pumpAndSettle();
      expect(find.text('The PINs did not match. Try again'), findsOneWidget);
      expect(find.text('Choose a PIN'), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('verify: wrong pin is refused, the right one returns it', (
      tester,
    ) async {
      final results = await pumpFlow(tester, PinFlowMode.verify, FakeLock());
      await tapPin(tester, '0000');
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(results, isEmpty);
      await tapPin(tester, '1234');
      await tester.pumpAndSettle();
      expect(results, ['1234']);
    });

    testWidgets('back returns null', (tester) async {
      final results = await pumpFlow(tester, PinFlowMode.verify, FakeLock());
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });
}
