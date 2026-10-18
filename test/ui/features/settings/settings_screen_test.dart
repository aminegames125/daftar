import 'package:daftar/app/routes/core_routes.dart';
import 'package:daftar/app/settings.dart';
import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/settings_repository.dart';
import 'package:daftar/domain/models/product.dart';
import 'package:daftar/ui/features/lock/services/lock_platform.dart';
import 'package:daftar/ui/features/lock/view_models/lock_controller.dart';
import 'package:daftar/ui/features/settings/views/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/test_app.dart';
import '../lock/lock_screen_test.dart' show FakeLock, tapPin;
import 'memory_settings_repository.dart';

class _RecordingLock extends FakeLock {
  _RecordingLock({super.initial});

  final List<String> enabledWith = [];
  bool disabled = false;
  String? changedTo;

  @override
  Future<void> enable(String pin, {required bool biometric}) async {
    enabledWith.add(pin);
    state = state.copyWith(enabled: true, locked: false, biometric: biometric);
  }

  @override
  Future<void> disable() async {
    disabled = true;
    state = state.copyWith(enabled: false);
  }

  @override
  Future<void> changePin(String newPin) async => changedTo = newPin;
}

class _FakeBiometric implements BiometricAuth {
  _FakeBiometric(this.available);
  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async => true;
}

void main() {
  late MemorySettingsRepository settings;
  late _RecordingLock lock;
  late ProviderContainer container;

  Future<void> pumpSettings(
    WidgetTester tester, {
    bool dark = true,
    bool reduce = true,
    double textScale = 1,
    Size size = const Size(412, 3200),
    AppLockState lockState = const AppLockState(ready: true),
    bool biometricAvailable = false,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    settings = MemorySettingsRepository();
    lock = _RecordingLock(initial: lockState);

    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (_, _) => Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/settings'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        ...coreRoutes.map((r) => r),
      ],
    );

    await tester.pumpWidget(
      testRouterApp(
        router,
        dark: dark,
        reduceMotion: reduce,
        textScale: textScale,
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          lockControllerProvider.overrideWith(() => lock),
          biometricAuthProvider.overrideWithValue(
            _FakeBiometric(biometricAvailable),
          ),
          initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
        ],
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows every section (dark) and fits at 130% text on a small phone (light)',
    (tester) async {
      await pumpSettings(tester);
      for (final text in [
        'Appearance',
        'Prices',
        'Manage lists',
        'Security',
        'Glass blur',
        'App lock',
        'Place types',
        'Categories',
        'Payment methods',
        'Global price types',
      ]) {
        expect(
          find.text(text.toUpperCase()).evaluate().isNotEmpty ||
              find.text(text).evaluate().isNotEmpty,
          isTrue,
          reason: text,
        );
      }
      expect(find.text('Daftar $appVersion'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pumpSettings(
        tester,
        dark: false,
        textScale: 1.3,
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('choosing a theme updates the mode and saves it', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.bySemanticsLabel('Light theme'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(settings.values[SettingKeys.themeMode], 'light');

    await tester.tap(find.bySemanticsLabel('System theme'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  testWidgets(
    'with animations on, the theme still changes (reveal falls back when nothing can be captured)',
    (tester) async {
      await pumpSettings(tester, reduce: false);
      await tester.tap(find.bySemanticsLabel('Light theme'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(themeModeProvider), ThemeMode.light);
    },
  );

  testWidgets('stale threshold and default unit are saved', (tester) async {
    await pumpSettings(tester);
    expect(container.read(staleDaysProvider), 90);

    await tester.tap(find.text('6 months'));
    await tester.pump();
    expect(container.read(staleDaysProvider), 180);
    expect(settings.values[SettingKeys.staleDays], '180');

    await tester.tap(find.text('kg'));
    await tester.pump();
    expect(container.read(defaultUnitProvider), SizeUnit.kg);
    expect(settings.values[SettingKeys.defaultUnit], 'kg');

    await tester.tap(find.text('None'));
    await tester.pump();
    expect(container.read(defaultUnitProvider), isNull);
  });

  testWidgets('a stale value that is not a preset gets its own chip', (
    tester,
  ) async {
    await pumpSettings(tester);
    await container.read(staleDaysProvider.notifier).set(45);
    await tester.pump();
    expect(find.text('45 days'), findsOneWidget);
  });

  testWidgets('glass blur switch is saved', (tester) async {
    await pumpSettings(tester);
    expect(container.read(glassBlurProvider), isTrue);
    await tester.tap(find.text('Glass blur'));
    await tester.pump();
    expect(container.read(glassBlurProvider), isFalse);
    expect(settings.values[AppSettingKeys.glassBlur], 'false');
  });

  testWidgets('list rows open their manage screens', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Place types'));
    await tester.pumpAndSettle();
    expect(find.text('Hold a row to move it · tap to rename'), findsOneWidget);
  });

  testWidgets('turning the app lock on asks for a PIN twice, then enables it', (
    tester,
  ) async {
    await pumpSettings(tester, biometricAvailable: true);
    await tester.tap(find.text('App lock'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a PIN'), findsOneWidget);
    await tapPin(tester, '4821');
    await tester.pumpAndSettle();
    await tapPin(tester, '4821');
    await tester.pumpAndSettle();

    expect(lock.enabledWith, ['4821']);
    expect(lock.current.biometric, isTrue); // offered because the phone has it
    expect(find.text('App lock is on'), findsOneWidget);
    expect(find.text('Change PIN'), findsOneWidget);
    expect(find.text('Fingerprint'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('turning it off needs the current PIN', (tester) async {
    await pumpSettings(
      tester,
      lockState: const AppLockState(ready: true, enabled: true),
    );
    await tester.tap(find.text('App lock'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);

    await tapPin(tester, '0000');
    await tester.pumpAndSettle();
    expect(lock.disabled, isFalse);

    await tapPin(tester, '1234');
    await tester.pumpAndSettle();
    expect(lock.disabled, isTrue);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('changing the PIN verifies the old one first', (tester) async {
    await pumpSettings(
      tester,
      lockState: const AppLockState(ready: true, enabled: true),
    );
    await tester.tap(find.text('Change PIN'));
    await tester.pumpAndSettle();
    await tapPin(tester, '1234');
    await tester.pumpAndSettle();
    expect(find.text('Choose a PIN'), findsOneWidget);
    await tapPin(tester, '7777');
    await tester.pumpAndSettle();
    await tapPin(tester, '7777');
    await tester.pumpAndSettle();
    expect(lock.changedTo, '7777');
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets(
    'lock options appear only when the lock is on; fingerprint only if the phone has it',
    (tester) async {
      await pumpSettings(tester);
      expect(find.text('Change PIN'), findsNothing);
      expect(find.text('Lock after leaving the app'), findsNothing);

      await pumpSettings(
        tester,
        lockState: const AppLockState(ready: true, enabled: true),
      );
      expect(find.text('Change PIN'), findsOneWidget);
      expect(find.text('Lock after leaving the app'), findsOneWidget);
      expect(find.text('Immediately'), findsOneWidget);
      expect(find.text('Fingerprint'), findsNothing);
    },
  );
}
