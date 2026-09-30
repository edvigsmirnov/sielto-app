import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// Argon2id: a slow profile for the Recovery Key, a fast one for the PIN.
abstract final class Kdf {
  static const int saltLength = 16;

  /// 1 MiB, one pass. Keeps parallel tests off the CPU-bound timing checks.
  @visibleForTesting
  static bool cheap = false;

  /// m=64 MiB, t=3, p=4.
  static Future<Uint8List> recoveryKey(String passphrase, List<int> salt) =>
      _derive(passphrase, salt, memory: 64 * 1024, iterations: 3, lanes: 4);

  /// m=19 MiB, t=2, p=1.
  static Future<Uint8List> pin(String pin, List<int> salt) =>
      _derive(pin, salt, memory: 19 * 1024, iterations: 2, lanes: 1);

  static Uint8List salt() {
    final Random rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(saltLength, (_) => rng.nextInt(256)),
    );
  }

  static Future<Uint8List> _derive(
    String secret,
    List<int> salt, {
    required int memory,
    required int iterations,
    required int lanes,
  }) {
    if (cheap) {
      memory = 1024;
      iterations = 1;
    }
    return Isolate.run(() async {
      final SecretKey key = await Argon2id(
        parallelism: lanes,
        memory: memory,
        iterations: iterations,
        hashLength: 32,
      ).deriveKeyFromPassword(password: secret, nonce: salt);
      return Uint8List.fromList(await key.extractBytes());
    });
  }
}
