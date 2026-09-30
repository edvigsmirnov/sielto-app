import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sielto/core/crypto/database_key.dart';
import 'package:sielto/core/crypto/envelope.dart';
import 'package:sielto/core/crypto/kdf.dart';

/// Storage for the envelope A wrapping key and the Recovery Key.
abstract class WrappingKeyStore {
  const WrappingKeyStore();

  /// Null when this device has none.
  Future<Uint8List?> read();

  Future<void> write(Uint8List key);

  /// A fresh wrapping key for a new envelope A.
  Future<Uint8List> newKey() async => DatabaseKey.generate().bytes;

  Future<String?> readRecoveryKey();

  Future<void> writeRecoveryKey(String recoveryKey);

  /// Clears both entries.
  Future<void> delete();
}

/// Keystore on Android, Credential Manager on Windows, libsecret on Linux.
class SecureStorageKeyStore extends WrappingKeyStore {
  const SecureStorageKeyStore({this.storage = const FlutterSecureStorage()});

  static const String _probe = 'keyring_probe';

  /// False where Linux has no running keyring.
  static Future<bool> works({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) async {
    if (const bool.fromEnvironment('SIELTO_NO_KEYRING')) return false;
    try {
      await storage.write(key: _probe, value: '1');
      final bool ok = await storage.read(key: _probe) == '1';
      await storage.delete(key: _probe);
      return ok;
    } on Exception {
      return false;
    }
  }

  static const String _key = 'envelope_a_wrapping_key';
  static const String _recoveryKey = 'recovery_key';

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
  Future<String?> readRecoveryKey() => storage.read(key: _recoveryKey);

  @override
  Future<void> writeRecoveryKey(String recoveryKey) =>
      storage.write(key: _recoveryKey, value: recoveryKey);

  @override
  Future<void> delete() async {
    await storage.delete(key: _key);
    await storage.delete(key: _recoveryKey);
  }
}

/// No keyring: the wrapping key comes from a password, with its salt beside
/// the envelope. The Recovery Key is kept for this run only.
class PassphraseKeyStore extends WrappingKeyStore {
  PassphraseKeyStore({required this.directory, required this.passphrase});

  final Directory directory;
  final String passphrase;
  String? _recoveryKey;

  File get _salt => File(p.join(directory.path, 'envelope_a.salt'));

  @override
  Future<Uint8List?> read() async => _salt.existsSync()
      ? Kdf.recoveryKey(passphrase, _salt.readAsBytesSync())
      : null;

  @override
  Future<Uint8List> newKey() async {
    final Uint8List salt = Kdf.salt();
    directory.createSync(recursive: true);
    _salt.writeAsBytesSync(salt, flush: true);
    return Kdf.recoveryKey(passphrase, salt);
  }

  @override
  Future<void> write(Uint8List key) async {}

  @override
  Future<String?> readRecoveryKey() async => _recoveryKey;

  @override
  Future<void> writeRecoveryKey(String recoveryKey) async =>
      _recoveryKey = recoveryKey;

  @override
  Future<void> delete() async {
    if (_salt.existsSync()) _salt.deleteSync();
  }
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

  /// Salt, then the envelope.
  File get envelopeBFile => File(p.join(directory.path, 'envelope_b.bin'));

  bool get hasRecoveryKey => envelopeBFile.existsSync();

  bool get usesPassphrase => _keyStore is PassphraseKeyStore;

  Future<String?> storedRecoveryKey() => _keyStore.readRecoveryKey();

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
    final DatabaseKey dek = DatabaseKey.generate();
    directory.createSync(recursive: true);
    await _writeEnvelopeA(dek);
    return dek;
  }

  /// A fresh wrapping key. The envelope is written first: a wrapping key
  /// without an envelope is recoverable, the reverse is not.
  Future<void> _writeEnvelopeA(DatabaseKey dek) async {
    final Uint8List wrappingKey = await _keyStore.newKey();
    final Envelope envelope = await Envelope.seal(
      dek,
      wrappingKey: wrappingKey,
    );
    _replace(envelopeAFile, envelope.bytes);
    await _keyStore.write(wrappingKey);
  }

  /// Seals the database key under [recoveryKey], replacing any earlier one.
  Future<void> setRecoveryKey(String recoveryKey) async =>
      _writeEnvelopeB(await resolve(), recoveryKey);

  /// Throws [EnvelopeException] when [current] is wrong.
  Future<void> changeRecoveryKey(String current, String next) async =>
      _writeEnvelopeB(await _openEnvelopeB(current), next);

  Future<bool> checkRecoveryKey(String recoveryKey) async {
    try {
      await _openEnvelopeB(recoveryKey);
      return true;
    } on EnvelopeException {
      return false;
    }
  }

  /// Opens envelope B and issues a new envelope A. Throws [EnvelopeException]
  /// when [recoveryKey] is wrong.
  Future<DatabaseKey> recover(String recoveryKey) async {
    final DatabaseKey dek = await _openEnvelopeB(recoveryKey);
    await _writeEnvelopeA(dek);
    await _keyStore.writeRecoveryKey(recoveryKey);
    return dek;
  }

  Future<void> _writeEnvelopeB(DatabaseKey dek, String recoveryKey) async {
    final Uint8List salt = Kdf.salt();
    final Envelope envelope = await Envelope.seal(
      dek,
      wrappingKey: await Kdf.recoveryKey(recoveryKey, salt),
    );
    _replace(envelopeBFile, <int>[...salt, ...envelope.bytes]);
    await _keyStore.writeRecoveryKey(recoveryKey);
  }

  Future<DatabaseKey> _openEnvelopeB(String recoveryKey) async {
    if (!hasRecoveryKey) {
      throw const EnvelopeException('no envelope B on this device');
    }
    final Uint8List bytes = envelopeBFile.readAsBytesSync();
    if (bytes.length <= Kdf.saltLength) {
      throw const EnvelopeException('envelope is truncated');
    }
    final Uint8List salt = bytes.sublist(0, Kdf.saltLength);
    return Envelope(bytes.sublist(Kdf.saltLength))
        .open(await Kdf.recoveryKey(recoveryKey, salt));
  }

  void _replace(File file, List<int> bytes) {
    final File temp = File('${file.path}.tmp')
      ..writeAsBytesSync(bytes, flush: true);
    temp.renameSync(file.path);
  }

  /// Discards the key and the envelope. Delete the database file in the same
  /// step.
  Future<void> destroy() async {
    await _keyStore.delete();
    for (final File f in <File>[envelopeAFile, envelopeBFile]) {
      if (f.existsSync()) f.deleteSync();
    }
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
