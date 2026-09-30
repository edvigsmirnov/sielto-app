import 'dart:io';

import 'package:drift/native.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sielto/core/crypto/database_key.dart';
import 'package:sielto/core/crypto/envelope.dart';
import 'package:sielto/core/crypto/key_store.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/time/space_clock.dart';

sealed class Startup {
  const Startup();
}

class StartupReady extends Startup {
  const StartupReady(this.database, this.manager);

  final AppDatabase database;
  final DatabaseKeyManager manager;
}

/// The database exists but its key is unavailable.
class StartupLocked extends Startup {
  const StartupLocked(this.reason, this.manager);

  final DatabaseKeyFailure reason;
  final DatabaseKeyManager manager;
}

/// Linux without a keyring: the database opens with a password.
class StartupNeedsPassphrase extends Startup {
  const StartupNeedsPassphrase(this.directory);

  final Directory directory;

  bool get firstRun =>
      !DatabaseKeyManager(directory: directory).envelopeAFile.existsSync();

  bool get canRecover =>
      DatabaseKeyManager(directory: directory).hasRecoveryKey;
}

/// [directory] is for tests. A wrong [passphrase] comes back as
/// [StartupLocked] with [DatabaseKeyFailure.envelopeUnreadable].
Future<Startup> openDatabase({Directory? directory, String? passphrase}) async {
  SpaceClock.initialize();

  final Directory dir = directory ?? await getApplicationSupportDirectory();
  if (passphrase == null &&
      Platform.isLinux &&
      !await SecureStorageKeyStore.works()) {
    return StartupNeedsPassphrase(dir);
  }
  final DatabaseKeyManager manager = DatabaseKeyManager(
    directory: dir,
    keyStore: passphrase == null
        ? null
        : PassphraseKeyStore(directory: dir, passphrase: passphrase),
  );

  final DatabaseKey key;
  try {
    key = await manager.resolve();
  } on DatabaseKeyUnavailable catch (e) {
    return StartupLocked(e.reason, manager);
  }

  return _ready(manager, key);
}

StartupReady _ready(DatabaseKeyManager manager, DatabaseKey key) =>
    StartupReady(
      AppDatabase(
        openEncryptedDatabase(directory: manager.directory, key: key),
      ),
      manager,
    );

/// Throws [EnvelopeException] when [recoveryKey] is wrong.
Future<Startup> recover(DatabaseKeyManager manager, String recoveryKey) async =>
    _ready(manager, await manager.recover(recoveryKey));

/// Deletes the database and its key material, then opens a fresh one.
Future<Startup> startOver(DatabaseKeyManager manager) async {
  await manager.destroy();
  for (final String suffix in <String>['', '-wal', '-shm']) {
    final File f = File(
      p.join(manager.directory.path, '$databaseFileName$suffix'),
    );
    if (f.existsSync()) f.deleteSync();
  }
  return openDatabase(directory: manager.directory);
}

/// Opens envelope B and seals envelope A under a new [passphrase].
Future<Startup> recoverWithPassphrase(
  Directory directory,
  String recoveryKey,
  String passphrase,
) => recover(
  DatabaseKeyManager(
    directory: directory,
    keyStore: PassphraseKeyStore(directory: directory, passphrase: passphrase),
  ),
  recoveryKey,
);

/// In-memory database with the full schema. Tests only.
@visibleForTesting
AppDatabase inMemoryDatabase() =>
    AppDatabase(NativeDatabase.memory(setup: registerSqlFunctions));
