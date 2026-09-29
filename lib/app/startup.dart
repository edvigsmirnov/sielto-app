import 'dart:io';

import 'package:drift/native.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sielto/core/crypto/database_key.dart';
import 'package:sielto/core/crypto/key_store.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/time/space_clock.dart';

sealed class Startup {
  const Startup();
}

class StartupReady extends Startup {
  const StartupReady(this.database);

  final AppDatabase database;
}

/// The database exists but its key is unavailable.
class StartupLocked extends Startup {
  const StartupLocked(this.reason, this.manager);

  final DatabaseKeyFailure reason;
  final DatabaseKeyManager manager;
}

/// [directory] is for tests.
Future<Startup> openDatabase({Directory? directory}) async {
  SpaceClock.initialize();

  final Directory dir = directory ?? await getApplicationSupportDirectory();
  final DatabaseKeyManager manager = DatabaseKeyManager(directory: dir);

  final DatabaseKey key;
  try {
    key = await manager.resolve();
  } on DatabaseKeyUnavailable catch (e) {
    return StartupLocked(e.reason, manager);
  }

  return StartupReady(
    AppDatabase(openEncryptedDatabase(directory: dir, key: key)),
  );
}

/// Deletes the database and its key material, then opens a fresh one.
Future<Startup> startOver(DatabaseKeyManager manager) async {
  await manager.destroy();
  for (final String suffix in <String>['', '-wal', '-shm']) {
    final File f = File('${manager.directory.path}/sielto.sqlite$suffix');
    if (f.existsSync()) f.deleteSync();
  }
  return openDatabase(directory: manager.directory);
}

/// In-memory database with the full schema. Tests only.
@visibleForTesting
AppDatabase inMemoryDatabase() => AppDatabase(NativeDatabase.memory());
