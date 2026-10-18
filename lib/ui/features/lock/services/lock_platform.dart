import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Hides the app in the recents screen (and blocks screenshots) via Android's
/// FLAG_SECURE. The native side is in `MainActivity.kt`.
class SecureScreen {
  const SecureScreen();

  static const MethodChannel _channel = MethodChannel(
    'com.amineos.daftar/secure',
  );

  Future<void> set({required bool secure}) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // Not running on Android (tests): nothing to do.
    } on PlatformException {
      // The flag is a privacy nicety; never block the app because of it.
    }
  }
}

/// Fingerprint / face unlock.
abstract interface class BiometricAuth {
  /// True when the phone has biometrics enrolled and can use them for us.
  Future<bool> isAvailable();

  /// Shows the system prompt. False when the user cancelled or it failed.
  Future<bool> authenticate(String reason);
}

class LocalBiometricAuth implements BiometricAuth {
  LocalBiometricAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // biometricOnly: the app has its own PIN, so the phone's PIN is not offered.
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final secureScreenProvider = Provider<SecureScreen>(
  (ref) => const SecureScreen(),
);

final biometricAuthProvider = Provider<BiometricAuth>(
  (ref) => LocalBiometricAuth(),
);
