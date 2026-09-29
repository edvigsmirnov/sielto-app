import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The 256-bit database key (DEK). Stored only inside envelopes.
@immutable
class DatabaseKey {
  const DatabaseKey(this.bytes);

  /// Generated once, at first install.
  factory DatabaseKey.generate() {
    final Random rng = Random.secure();
    return DatabaseKey(
      Uint8List.fromList(List<int>.generate(length, (_) => rng.nextInt(256))),
    );
  }

  factory DatabaseKey.fromBase64(String encoded) =>
      DatabaseKey(base64Decode(encoded));

  static const int length = 32;

  final Uint8List bytes;

  String toBase64() => base64Encode(bytes);

  /// `x'<hex>'` passes the raw key and skips SQLCipher's KDF. Single quotes:
  /// this build rejects double-quoted strings (SQLITE_DQS=0).
  String toPragmaLiteral() {
    final String hex = bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return "'x''$hex'''";
  }

  @override
  bool operator ==(Object other) {
    if (other is! DatabaseKey || other.bytes.length != bytes.length) {
      return false;
    }
    // Constant time.
    int diff = 0;
    for (int i = 0; i < bytes.length; i++) {
      diff |= bytes[i] ^ other.bytes[i];
    }
    return diff == 0;
  }

  @override
  int get hashCode => bytes.length;

  /// Never print key material.
  @override
  String toString() => 'DatabaseKey(32 bytes)';
}
