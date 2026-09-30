import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/crypto/database_key.dart';
import 'package:sielto/core/crypto/envelope.dart';
import 'package:sielto/core/crypto/kdf.dart';
import 'package:sielto/core/crypto/key_store.dart';

/// In-memory keystore.
class _MemoryKeyStore extends WrappingKeyStore {
  Uint8List? _key;
  String? _recoveryKey;

  @override
  Future<Uint8List?> read() async => _key;

  @override
  Future<void> write(Uint8List key) async => _key = key;

  @override
  Future<String?> readRecoveryKey() async => _recoveryKey;

  @override
  Future<void> writeRecoveryKey(String recoveryKey) async =>
      _recoveryKey = recoveryKey;

  @override
  Future<void> delete() async {
    _key = null;
    _recoveryKey = null;
  }
}

void main() {
  late Directory dir;
  late _MemoryKeyStore keyStore;

  DatabaseKeyManager manager() =>
      DatabaseKeyManager(directory: dir, keyStore: keyStore);

  setUpAll(() => Kdf.cheap = true);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('budget_keystore_');
    keyStore = _MemoryKeyStore();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('first run mints a key and writes envelope A', () async {
    final DatabaseKey key = await manager().resolve();

    expect(key.bytes, hasLength(32));
    expect(manager().envelopeAFile.existsSync(), isTrue);
    expect(await keyStore.read(), isNotNull);
  });

  test('a later run returns the same key', () async {
    final DatabaseKey first = await manager().resolve();
    final DatabaseKey second = await manager().resolve();
    expect(second, first);
  });

  test('a lost keystore entry reports the recoverable failure', () async {
    await manager().resolve();
    // Keystore entry lost, envelope kept.
    await keyStore.delete();

    expect(
      manager().resolve(),
      throwsA(
        isA<DatabaseKeyUnavailable>().having(
          (DatabaseKeyUnavailable e) => e.reason,
          'reason',
          DatabaseKeyFailure.wrappingKeyMissing,
        ),
      ),
    );
  });

  test('a missing envelope is reported separately', () async {
    await manager().resolve();
    manager().envelopeAFile.deleteSync();

    expect(
      manager().resolve(),
      throwsA(
        isA<DatabaseKeyUnavailable>().having(
          (DatabaseKeyUnavailable e) => e.reason,
          'reason',
          DatabaseKeyFailure.envelopeMissing,
        ),
      ),
    );
  });

  test('a corrupted envelope is reported as unreadable', () async {
    await manager().resolve();
    final File file = manager().envelopeAFile;
    final Uint8List bytes = file.readAsBytesSync();
    bytes[bytes.length - 1] ^= 0xFF;
    file.writeAsBytesSync(bytes);

    expect(
      manager().resolve(),
      throwsA(
        isA<DatabaseKeyUnavailable>().having(
          (DatabaseKeyUnavailable e) => e.reason,
          'reason',
          DatabaseKeyFailure.envelopeUnreadable,
        ),
      ),
    );
  });

  test('destroy clears both halves, and the next run starts fresh', () async {
    final DatabaseKey first = await manager().resolve();
    await manager().destroy();

    expect(manager().envelopeAFile.existsSync(), isFalse);
    expect(await keyStore.read(), isNull);
    expect(await manager().resolve(), isNot(first));
  });

  test('the envelope file does not contain the key', () async {
    final DatabaseKey key = await manager().resolve();
    final String onDisk = manager().envelopeAFile.readAsBytesSync().join(',');
    expect(onDisk, isNot(contains(key.bytes.join(','))));
  });

  test(
    'the Recovery Key reopens a lost keystore and reissues envelope A',
    () async {
      final DatabaseKey key = await manager().resolve();
      expect(manager().hasRecoveryKey, isFalse);
      await manager().setRecoveryKey('correct horse');
      expect(manager().hasRecoveryKey, isTrue);
      expect(await keyStore.readRecoveryKey(), 'correct horse');

      await keyStore.delete();
      await expectLater(
        manager().resolve(),
        throwsA(isA<DatabaseKeyUnavailable>()),
      );

      await expectLater(
        manager().recover('wrong horse'),
        throwsA(isA<EnvelopeException>()),
      );
      expect(await manager().recover('correct horse'), key);
      expect(await manager().resolve(), key);
      expect(await keyStore.readRecoveryKey(), 'correct horse');
    },
  );

  test('changing the Recovery Key needs the current one', () async {
    final DatabaseKey key = await manager().resolve();
    await manager().setRecoveryKey('first key');

    await expectLater(
      manager().changeRecoveryKey('not it', 'second key'),
      throwsA(isA<EnvelopeException>()),
    );
    await manager().changeRecoveryKey('first key', 'second key');

    expect(await manager().checkRecoveryKey('first key'), isFalse);
    expect(await manager().checkRecoveryKey('second key'), isTrue);
    await keyStore.delete();
    expect(await manager().recover('second key'), key);
  });

  test('destroy removes envelope B as well', () async {
    await manager().resolve();
    await manager().setRecoveryKey('correct horse');
    await manager().destroy();
    expect(manager().hasRecoveryKey, isFalse);
  });

  test('a password stands in for the keyring', () async {
    DatabaseKeyManager withPassword(String password) => DatabaseKeyManager(
      directory: dir,
      keyStore: PassphraseKeyStore(directory: dir, passphrase: password),
    );

    final DatabaseKey key = await withPassword('hunter22').resolve();
    await withPassword('hunter22').setRecoveryKey('correct horse');
    expect(await withPassword('hunter22').resolve(), key);
    await expectLater(
      withPassword('hunter23').resolve(),
      throwsA(
        isA<DatabaseKeyUnavailable>().having(
          (DatabaseKeyUnavailable e) => e.reason,
          'reason',
          DatabaseKeyFailure.envelopeUnreadable,
        ),
      ),
    );

    expect(await withPassword('new pass').recover('correct horse'), key);
    expect(await withPassword('new pass').resolve(), key);
  });
}
