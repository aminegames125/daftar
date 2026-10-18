import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted, iterated HMAC-SHA256 hashing of the app-lock PIN. The PIN itself is
/// never stored, only `salt` and `hash`.
abstract final class PinHasher {
  /// Rounds of HMAC. A 4-digit PIN is brute-forceable offline whatever we do;
  /// the rounds only slow a casual attacker. Online guessing is limited by
  /// [PinAttemptGuard].
  static const int rounds = 10000;

  static String newSalt([Random? random]) {
    final rng = random ?? Random.secure();
    return base64UrlEncode([for (var i = 0; i < 16; i++) rng.nextInt(256)]);
  }

  static String hash(String pin, String salt) {
    final key = utf8.encode(salt);
    final data = utf8.encode(pin);
    final hmac = Hmac(sha256, key);
    var digest = hmac.convert(data).bytes;
    for (var i = 0; i < rounds; i++) {
      digest = hmac.convert([...digest, ...data]).bytes;
    }
    return base64UrlEncode(digest);
  }

  /// Compares in constant time.
  static bool verify(
    String pin, {
    required String salt,
    required String expectedHash,
  }) {
    final a = utf8.encode(hash(pin, salt));
    final b = utf8.encode(expectedHash);
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Slows down PIN guessing: after [maxAttempts] wrong tries in a row, entry is
/// blocked for [lockout]. Kept in memory (restarting the app resets it).
class PinAttemptGuard {
  PinAttemptGuard({
    this.maxAttempts = 5,
    this.lockout = const Duration(seconds: 30),
  });

  final int maxAttempts;
  final Duration lockout;

  int _failures = 0;
  DateTime? _blockedUntil;

  /// Time left before another try is allowed; zero when allowed.
  Duration remaining(DateTime now) {
    final until = _blockedUntil;
    if (until == null || !now.isBefore(until)) return Duration.zero;
    return until.difference(now);
  }

  bool isBlocked(DateTime now) => remaining(now) > Duration.zero;

  void recordFailure(DateTime now) {
    _failures++;
    if (_failures >= maxAttempts) {
      _blockedUntil = now.add(lockout);
      _failures = 0;
    }
  }

  void recordSuccess() {
    _failures = 0;
    _blockedUntil = null;
  }
}
