import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sielto/core/crypto/database_key.dart';
import 'package:sielto/core/crypto/envelope.dart';

/// Storage for the envelope A wrapping key.
abstract class WrappingKeyStore {
  /// Null when this device has none.
  Future<Uint8List?> read();

  Future<void> write(Uint8List key);

  Future<void> delete();
}

/// Keystore on Android, Credential Manager on Windows, libsecret on Linux.
class SecureStorageKeyStore implements WrappingKeyStore {
  const SecureStorageKeyStore({this.storage = const FlutterSecureStorage()});

  static const String _key = 'envelope_a_wrapping_key';

  final FlutterSecureStorage storage;

  @override
  Future<Uint8List?> read() async {
    final String? encoded = await storage.read(key: _key);
    return encoded == null ? null : base64Decode(encoded);
  }

  @override
  Future<void> write(Uint8List key) =>
      storage.write(key: _key, value: base64Encode(key));

  @override
  Future<void> delete() => storage.delete(key: _key);
}

/// Resolves the database key at startup. Throws [DatabaseKeyUnavailable] when
/// the envelope does not open.
class DatabaseKeyManager {
  DatabaseKeyManager({required this.directory, WrappingKeyStore? keyStore})
    : _keyStore = keyStore ?? const SecureStorageKeyStore();

  /// Holds the database and its envelopes.
  final Directory directory;
  final WrappingKeyStore _keyStore;

  File get envelopeAFile => File(p.join(directory.path, 'envelope_a.bin'));

  /// Creates the key on first run.
  Future<DatabaseKey> resolve() async {
    final bool hasEnvelope = envelopeAFile.existsSync();
    final Uint8List? wrappingKey = await _keyStore.read();

    if (!hasEnvelope && wrappingKey == null) return _createFirstRun();

    if (wrappingKey == null) {
      throw const DatabaseKeyUnavailable(DatabaseKeyFailure.wrappingKeyMissing);
    }
    if (!hasEnvelope) {
      // Safe to start over only when no database exists; the caller decides.
      throw const DatabaseKeyUnavailable(DatabaseKeyFailure.envelopeMissing);
    }

    try {
      return await Envelope(envelopeAFile.readAsBytesSync()).open(wrappingKey);
    } on EnvelopeException {
      throw const DatabaseKeyUnavailable(DatabaseKeyFailure.envelopeUnreadable);
    }
  }

  Future<DatabaseKey> _createFirstRun() async {
    final Uint8List wrappingKey = DatabaseKey.generate().bytes;
    final DatabaseKey dek = DatabaseKey.generate();

    final Envelope envelope = await Envelope.seal(
      dek,
      wrappingKey: wrappingKey,
    );
    directory.createSync(recursive: true);
    envelopeAFile.writeAsBytesSync(envelope.bytes, flush: true);
    // Written after the envelope: a wrapping key without an envelope is
    // recoverable, the reverse is not.
    await _keyStore.write(wrappingKey);

    return dek;
  }

  /// Discards the key and the envelope. Delete the database file in the same
  /// step.
  Future<void> destroy() async {
    await _keyStore.delete();
    if (envelopeAFile.existsSync()) envelopeAFile.deleteSync();
  }
}

enum DatabaseKeyFailure {
  /// Envelope present, keystore entry gone.
  wrappingKeyMissing,

  /// Keystore entry present, envelope gone.
  envelopeMissing,

  /// Both present; the envelope does not open.
  envelopeUnreadable,
}

class DatabaseKeyUnavailable implements Exception {
  const DatabaseKeyUnavailable(this.reason);

  final DatabaseKeyFailure reason;

  @override
  String toString() => 'DatabaseKeyUnavailable: ${reason.name}';
}
