import 'dart:async';

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/repositories/settings_repository.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/ui/features/lock/services/lock_platform.dart';
import 'package:daftar/ui/features/lock/services/pin_hasher.dart';
import 'package:daftar/ui/features/lock/view_models/lock_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBiometric implements BiometricAuth {
  FakeBiometric({this.available = true, this.succeeds = true});
  bool available;
  bool succeeds;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeeds;
  }
}

class FakeSecureScreen extends SecureScreen {
  final List<bool> calls = [];

  @override
  Future<void> set({required bool secure}) async => calls.add(secure);
}

void main() {
  group('PinHasher', () {
    test('same pin and salt give the same hash; salt and pin both matter', () {
      final salt = PinHasher.newSalt();
      expect(PinHasher.hash('1234', salt), PinHasher.hash('1234', salt));
      expect(PinHasher.hash('1234', salt), isNot(PinHasher.hash('1235', salt)));
      expect(
        PinHasher.hash('1234', salt),
        isNot(PinHasher.hash('1234', PinHasher.newSalt())),
      );
    });

    test('the hash does not contain the pin and salts are random', () {
      final salt = PinHasher.newSalt();
      expect(PinHasher.hash('1234', salt), isNot(contains('1234')));
      expect(PinHasher.newSalt(), isNot(salt));
    });

    test('verify accepts only the right pin', () {
      final salt = PinHasher.newSalt();
      final hash = PinHasher.hash('4821', salt);
      expect(PinHasher.verify('4821', salt: salt, expectedHash: hash), isTrue);
      expect(PinHasher.verify('4822', salt: salt, expectedHash: hash), isFalse);
      expect(PinHasher.verify('4821', salt: salt, expectedHash: ''), isFalse);
    });
  });

  group('PinAttemptGuard', () {
    final t0 = DateTime(2026, 10, 16, 12);

    test('blocks after five failures for 30 seconds, then allows again', () {
      final guard = PinAttemptGuard();
      for (var i = 0; i < 4; i++) {
        guard.recordFailure(t0);
        expect(guard.isBlocked(t0), isFalse);
      }
      guard.recordFailure(t0);
      expect(guard.isBlocked(t0), isTrue);
      expect(
        guard.remaining(t0.add(const Duration(seconds: 10))),
        const Duration(seconds: 20),
      );
      expect(guard.isBlocked(t0.add(const Duration(seconds: 30))), isFalse);
    });

    test('a success resets the count', () {
      final guard = PinAttemptGuard();
      for (var i = 0; i < 4; i++) {
        guard.recordFailure(t0);
      }
      guard.recordSuccess();
      guard.recordFailure(t0);
      expect(guard.isBlocked(t0), isFalse);
    });
  });

  group('LockController', () {
    late AppDatabase db;
    late FakeBiometric biometric;
    late FakeSecureScreen secure;
    late DateTime clock;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      biometric = FakeBiometric();
      secure = FakeSecureScreen();
      clock = DateTime(2026, 10, 16, 12);
    });
    tearDown(() => db.close());

    ProviderContainer newApp() {
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          biometricAuthProvider.overrideWithValue(biometric),
          secureScreenProvider.overrideWithValue(secure),
          lockClockProvider.overrideWithValue(() => clock),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<AppLockState> ready(ProviderContainer c) async {
      final done = Completer<AppLockState>();
      final sub = c.listen(lockControllerProvider, (_, s) {
        if (s.ready && !done.isCompleted) done.complete(s);
      }, fireImmediately: true);
      final s = await done.future.timeout(const Duration(seconds: 5));
      sub.close();
      return s;
    }

    test('a fresh install has no lock and is not covered', () async {
      final s = await ready(newApp());
      expect(s.enabled, isFalse);
      expect(s.locked, isFalse);
    });

    test('enable stores a salted hash (never the pin), keeps this session open and secures the screen', () async {
      final c = newApp();
      await ready(c);
      await c
          .read(lockControllerProvider.notifier)
          .enable('4821', biometric: true);

      final s = c.read(lockControllerProvider);
      expect(s.enabled, isTrue);
      expect(s.locked, isFalse);
      expect(s.biometric, isTrue);
      expect(secure.calls.last, isTrue);

      final repo = DriftSettingsRepository(db);
      final hash = await repo.get(LockSettingKeys.pinHash);
      expect(hash, isNotEmpty);
      expect(hash, isNot(contains('4821')));
      expect(await repo.get(LockSettingKeys.pinSalt), isNotEmpty);
      expect(await repo.get(SettingKeys.lockEnabled), 'true');
    });

    test(
      'after a restart the app opens locked, and the right pin unlocks it',
      () async {
        final first = newApp();
        await ready(first);
        await first
            .read(lockControllerProvider.notifier)
            .enable('4821', biometric: false);

        final restarted = newApp();
        final s = await ready(restarted);
        expect(s.enabled, isTrue);
        expect(s.locked, isTrue);
        expect(secure.calls.last, isTrue);

        final lock = restarted.read(lockControllerProvider.notifier);
        expect(await lock.unlockWithPin('0000'), PinCheck.wrong);
        expect(restarted.read(lockControllerProvider).locked, isTrue);
        expect(await lock.unlockWithPin('4821'), PinCheck.ok);
        expect(restarted.read(lockControllerProvider).locked, isFalse);
      },
    );

    test(
      'five wrong pins block entry for 30 seconds, even for the right pin',
      () async {
        final c = newApp();
        await ready(c);
        final lock = c.read(lockControllerProvider.notifier);
        await lock.enable('4821', biometric: false);
        lock.lockNow();

        for (var i = 0; i < 4; i++) {
          expect(await lock.unlockWithPin('1111'), PinCheck.wrong);
        }
        expect(await lock.unlockWithPin('1111'), PinCheck.blocked);
        expect(await lock.unlockWithPin('4821'), PinCheck.blocked);
        expect(lock.blockedSeconds(), 30);

        clock = clock.add(const Duration(seconds: 31));
        expect(await lock.unlockWithPin('4821'), PinCheck.ok);
      },
    );

    test('changePin replaces the pin', () async {
      final c = newApp();
      await ready(c);
      final lock = c.read(lockControllerProvider.notifier);
      await lock.enable('4821', biometric: false);
      await lock.changePin('9999');
      expect(await lock.checkPin('4821'), PinCheck.wrong);
      expect(await lock.checkPin('9999'), PinCheck.ok);
    });

    test('disable forgets the pin and the next start is open', () async {
      final c = newApp();
      await ready(c);
      final lock = c.read(lockControllerProvider.notifier);
      await lock.enable('4821', biometric: true);
      await lock.disable();
      expect(c.read(lockControllerProvider).enabled, isFalse);
      expect(secure.calls.last, isFalse);

      final restarted = newApp();
      final s = await ready(restarted);
      expect(s.enabled, isFalse);
      expect(s.locked, isFalse);
    });

    test('re-locks only after the chosen time in the background', () async {
      final c = newApp();
      await ready(c);
      final lock = c.read(lockControllerProvider.notifier);
      await lock.enable('4821', biometric: false);
      await lock.setDelay(const Duration(seconds: 30));

      lock.onBackgrounded();
      clock = clock.add(const Duration(seconds: 10));
      lock.onResumed();
      expect(c.read(lockControllerProvider).locked, isFalse);

      lock.onBackgrounded();
      clock = clock.add(const Duration(seconds: 31));
      lock.onResumed();
      expect(c.read(lockControllerProvider).locked, isTrue);
    });

    test(
      '"immediately" locks on every return; no lock when it is off',
      () async {
        final c = newApp();
        await ready(c);
        final lock = c.read(lockControllerProvider.notifier);

        lock.onBackgrounded();
        lock.onResumed();
        expect(c.read(lockControllerProvider).locked, isFalse);

        await lock.enable('4821', biometric: false);
        await lock.setDelay(Duration.zero);
        lock.onBackgrounded();
        lock.onResumed();
        expect(c.read(lockControllerProvider).locked, isTrue);
      },
    );

    test('fingerprint unlocks only when it is switched on', () async {
      final c = newApp();
      await ready(c);
      final lock = c.read(lockControllerProvider.notifier);
      await lock.enable('4821', biometric: false);
      lock.lockNow();
      expect(await lock.unlockWithBiometric(), isFalse);
      expect(biometric.prompts, 0);

      await lock.setBiometric(enabled: true);
      biometric.succeeds = false;
      expect(await lock.unlockWithBiometric(), isFalse);
      expect(c.read(lockControllerProvider).locked, isTrue);

      biometric.succeeds = true;
      expect(await lock.unlockWithBiometric(), isTrue);
      expect(c.read(lockControllerProvider).locked, isFalse);
    });

    test('the saved delay and fingerprint choice survive a restart', () async {
      final c = newApp();
      await ready(c);
      final lock = c.read(lockControllerProvider.notifier);
      await lock.enable('4821', biometric: true);
      await lock.setDelay(const Duration(minutes: 5));

      final s = await ready(newApp());
      expect(s.delay, const Duration(minutes: 5));
      expect(s.biometric, isTrue);
    });
  });
}
