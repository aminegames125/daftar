import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../services/lock_platform.dart';
import '../services/pin_hasher.dart';

/// Extra `settings` keys of the app lock (the enable flag is
/// [SettingKeys.lockEnabled]).
abstract final class LockSettingKeys {
  static const pinSalt = 'lock_pin_salt';
  static const pinHash = 'lock_pin_hash';

  /// 'true' / 'false': also unlock with fingerprint / face.
  static const biometric = 'lock_biometric';

  /// Seconds the app may stay in the background before it locks again.
  static const delaySeconds = 'lock_delay_seconds';
}

/// How long the app may be left before it locks again. The camera, gallery and
/// permission dialogs also send the app to the background, so "immediately" can be
/// annoying: the default is 30 seconds.
const List<Duration> lockDelayChoices = [
  Duration.zero,
  Duration(seconds: 30),
  Duration(minutes: 5),
];
const Duration defaultLockDelay = Duration(seconds: 30);

/// PIN length. Four digits, as in the motion library.
const int pinLength = 4;

enum PinCheck { ok, wrong, blocked }

class AppLockState {
  const AppLockState({
    this.ready = false,
    this.enabled = false,
    this.locked = false,
    this.biometric = false,
    this.delay = defaultLockDelay,
  });

  /// False until the saved settings have been read; the UI keeps the app covered.
  final bool ready;

  /// The user turned the app lock on (and has a PIN).
  final bool enabled;

  /// The lock screen is showing.
  final bool locked;

  /// Fingerprint / face unlock is on (needs [enabled]).
  final bool biometric;
  final Duration delay;

  AppLockState copyWith({
    bool? ready,
    bool? enabled,
    bool? locked,
    bool? biometric,
    Duration? delay,
  }) => AppLockState(
    ready: ready ?? this.ready,
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    biometric: biometric ?? this.biometric,
    delay: delay ?? this.delay,
  );
}

final lockControllerProvider = NotifierProvider<LockController, AppLockState>(
  LockController.new,
);

/// Source of the time, replaced in tests.
final lockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class LockController extends Notifier<AppLockState> {
  final PinAttemptGuard _guard = PinAttemptGuard();
  DateTime? _backgroundedAt;

  @override
  AppLockState build() {
    _load();
    return const AppLockState();
  }

  DateTime _now() => ref.read(lockClockProvider)();

  Future<void> _load() async {
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final enabled =
          await repo.get(SettingKeys.lockEnabled) == 'true' &&
          (await repo.get(LockSettingKeys.pinHash))?.isNotEmpty == true;
      final biometric = await repo.get(LockSettingKeys.biometric) == 'true';
      final seconds = int.tryParse(
        await repo.get(LockSettingKeys.delaySeconds) ?? '',
      );
      if (!ref.mounted) return;
      state = AppLockState(
        ready: true,
        enabled: enabled,
        locked: enabled, // a cold start always opens locked
        biometric: enabled && biometric,
        delay: seconds == null ? defaultLockDelay : Duration(seconds: seconds),
      );
      await ref.read(secureScreenProvider).set(secure: enabled);
    } catch (_) {
      // No readable database: do not lock the user out of an app that has no lock.
      if (ref.mounted) state = const AppLockState(ready: true);
    }
  }

  /// Turns the lock on with a new [pin]. The app stays unlocked for this session.
  Future<void> enable(String pin, {required bool biometric}) async {
    final repo = ref.read(settingsRepositoryProvider);
    final salt = PinHasher.newSalt();
    await repo.set(LockSettingKeys.pinSalt, salt);
    await repo.set(LockSettingKeys.pinHash, PinHasher.hash(pin, salt));
    await repo.set(LockSettingKeys.biometric, '$biometric');
    await repo.set(SettingKeys.lockEnabled, 'true');
    _guard.recordSuccess();
    state = state.copyWith(
      ready: true,
      enabled: true,
      locked: false,
      biometric: biometric,
    );
    await ref.read(secureScreenProvider).set(secure: true);
  }

  /// Turns the lock off and forgets the PIN. Callers must have verified the PIN first.
  Future<void> disable() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.set(SettingKeys.lockEnabled, 'false');
    await repo.set(LockSettingKeys.pinHash, '');
    await repo.set(LockSettingKeys.pinSalt, '');
    await repo.set(LockSettingKeys.biometric, 'false');
    state = state.copyWith(enabled: false, locked: false, biometric: false);
    await ref.read(secureScreenProvider).set(secure: false);
  }

  /// Replaces the PIN. Callers must have verified the old one first.
  Future<void> changePin(String newPin) async {
    final repo = ref.read(settingsRepositoryProvider);
    final salt = PinHasher.newSalt();
    await repo.set(LockSettingKeys.pinSalt, salt);
    await repo.set(LockSettingKeys.pinHash, PinHasher.hash(newPin, salt));
    _guard.recordSuccess();
  }

  Future<void> setBiometric({required bool enabled}) async {
    await ref
        .read(settingsRepositoryProvider)
        .set(LockSettingKeys.biometric, '$enabled');
    state = state.copyWith(biometric: enabled);
  }

  Future<void> setDelay(Duration delay) async {
    await ref
        .read(settingsRepositoryProvider)
        .set(LockSettingKeys.delaySeconds, '${delay.inSeconds}');
    state = state.copyWith(delay: delay);
  }

  /// Seconds before PIN entry is allowed again (0 when allowed).
  int blockedSeconds() =>
      (_guard.remaining(_now()).inMilliseconds / 1000).ceil();

  /// Checks [pin] against the saved hash. Too many wrong tries block entry for a while.
  Future<PinCheck> checkPin(String pin) async {
    final now = _now();
    if (_guard.isBlocked(now)) return PinCheck.blocked;
    final repo = ref.read(settingsRepositoryProvider);
    final salt = await repo.get(LockSettingKeys.pinSalt) ?? '';
    final hash = await repo.get(LockSettingKeys.pinHash) ?? '';
    final ok =
        hash.isNotEmpty &&
        PinHasher.verify(pin, salt: salt, expectedHash: hash);
    if (ok) {
      _guard.recordSuccess();
      return PinCheck.ok;
    }
    _guard.recordFailure(now);
    return _guard.isBlocked(now) ? PinCheck.blocked : PinCheck.wrong;
  }

  /// Lock-screen PIN entry. Unlocks on success.
  Future<PinCheck> unlockWithPin(String pin) async {
    final result = await checkPin(pin);
    if (result == PinCheck.ok) state = state.copyWith(locked: false);
    return result;
  }

  Future<bool> biometricAvailable() =>
      ref.read(biometricAuthProvider).isAvailable();

  /// Shows the fingerprint prompt; unlocks on success.
  Future<bool> unlockWithBiometric() async {
    if (!state.enabled || !state.biometric) return false;
    final ok = await ref
        .read(biometricAuthProvider)
        .authenticate('Unlock Daftar');
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }

  void lockNow() {
    if (state.enabled) state = state.copyWith(locked: true);
  }

  /// The app left the foreground.
  void onBackgrounded() => _backgroundedAt ??= _now();

  /// The app is back: lock again if it was away for at least [AppLockState.delay].
  void onResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || !state.enabled) return;
    if (_now().difference(since) >= state.delay) lockNow();
  }
}

/// Whether this phone has fingerprint / face unlock set up (offered in Settings).
final biometricAvailableProvider = FutureProvider<bool>(
  (ref) => ref.read(biometricAuthProvider).isAvailable(),
);
