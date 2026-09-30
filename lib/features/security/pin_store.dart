import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sielto/core/crypto/kdf.dart';

/// Nothing for the first three failures, then 5 s, 15 s, 30 s, 60 s, and
/// doubling up to an hour.
Duration lockoutFor(int failures) {
  if (failures < 3) return Duration.zero;
  const List<int> steps = <int>[5, 15, 30, 60];
  final int i = failures - 3;
  return Duration(
    seconds: i < steps.length ? steps[i] : min(60 << (i - 3), 3600),
  );
}

/// The app lock PIN as an Argon2id hash, and the failure count. A UI lock:
/// anyone with full access to the device can clear both.
class PinStore {
  const PinStore({this.storage = const FlutterSecureStorage()});

  static const String _pin = 'app_lock_pin';
  static const String _failures = 'app_lock_failures';

  final FlutterSecureStorage storage;

  Future<bool> isSet() async => await storage.read(key: _pin) != null;

  Future<void> set(String pin) async {
    final Uint8List salt = Kdf.salt();
    final Uint8List hash = await Kdf.pin(pin, salt);
    await storage.write(
      key: _pin,
      value: '${base64Encode(salt)}:${base64Encode(hash)}',
    );
    await storage.delete(key: _failures);
  }

  Future<void> clear() async {
    await storage.delete(key: _pin);
    await storage.delete(key: _failures);
  }

  /// Null when [pin] is right. Otherwise when the next attempt is allowed,
  /// which may be [now]. An attempt during a lockout is not counted.
  Future<DateTime?> check(String pin, DateTime now) async {
    final ({int failures, DateTime until}) past = await _readFailures(now);
    if (now.isBefore(past.until)) return past.until;

    final String? stored = await storage.read(key: _pin);
    if (stored == null) return null;
    final List<String> parts = stored.split(':');
    final Uint8List hash = await Kdf.pin(pin, base64Decode(parts[0]));
    if (_equal(hash, base64Decode(parts[1]))) {
      await storage.delete(key: _failures);
      return null;
    }
    final int failures = past.failures + 1;
    final DateTime until = now.add(lockoutFor(failures));
    await storage.write(
      key: _failures,
      value: '$failures:${until.toUtc().toIso8601String()}',
    );
    return until;
  }

  /// When the next attempt is allowed.
  Future<DateTime> retryAt(DateTime now) async =>
      (await _readFailures(now)).until;

  Future<({int failures, DateTime until})> _readFailures(DateTime now) async {
    final String? raw = await storage.read(key: _failures);
    if (raw == null) return (failures: 0, until: now);
    final int split = raw.indexOf(':');
    return (
      failures: int.parse(raw.substring(0, split)),
      until: DateTime.parse(raw.substring(split + 1)),
    );
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
