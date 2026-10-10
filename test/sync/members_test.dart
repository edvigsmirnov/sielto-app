import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/sync/cloud_identity.dart';
import 'package:sielto/core/sync/sync_worker.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

void main() {
  final String? url = Platform.environment['SIELTO_SUPABASE_TEST_URL'];
  final String? key = Platform.environment['SIELTO_SUPABASE_TEST_KEY'];
  final String? skip = url == null || key == null
      ? 'no local Supabase configured'
      : null;

  setUpAll(() {
    SpaceClock.initialize();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test(
    'an invited person joins a Space, sees it, and loses it when removed',
    () async {
      SupabaseClient client() => SupabaseClient(
        url!,
        key!,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      final String owner = const Uuid().v4();
      final String guest = const Uuid().v4();
      final AppDatabase a = inMemoryDatabase();
      final AppDatabase b = inMemoryDatabase();
      final SupabaseClient clientA = client();
      final SupabaseClient clientB = client();
      final CloudIdentity identityA = CloudIdentity(
        db: a,
        client: clientA,
        userId: owner,
      );
      final CloudIdentity identityB = CloudIdentity(
        db: b,
        client: clientB,
        userId: guest,
      );
      addTearDown(() async {
        await identityA.dispose();
        await identityB.dispose();
        await a.close();
        await b.close();
      });

      await identityA.ensure();
      await identityB.ensure();
      final SpaceRepository spacesA = SpaceRepository(
        db: a,
        clock: SpaceClock(timezone: 'UTC'),
      );
      final String spaceId = (await spacesA.create(
        title: 'Family',
        spaceType: SpaceType.family,
        budgetMode: BudgetMode.flow,
        ownerId: owner,
        timezone: 'UTC',
        currencyCode: 'EUR',
        storageMode: StorageMode.cloud,
      )).id;
      await spacesA.setMaxMembers(spaceId, 2);
      await SyncWorker(db: a, client: clientA).syncAll();

      final String code = await clientA.rpc<String>(
        'create_space_invite',
        params: <String, String>{'p_space_id': spaceId},
      );
      expect(
        await clientB.rpc<String?>(
          'join_space_by_token',
          params: <String, String>{'p_code': code},
        ),
        spaceId,
      );
      await SyncWorker(db: b, client: clientB).syncAll();
      final Space joined = await (b.select(
        b.spaces,
      )..where(($SpacesTable t) => t.id.equals(spaceId))).getSingle();
      expect(joined.title, 'Family');
      expect(joined.ownerId, owner);

      await clientA.rpc<void>(
        'remove_member',
        params: <String, String>{'p_space_id': spaceId, 'p_user_id': guest},
      );
      final SyncWorker workerB = SyncWorker(db: b, client: clientB);
      expect(await workerB.anyVanished(), isTrue);
      await workerB.syncAll();
      expect(workerB.vanished, <String>[spaceId]);
      final Space removed = await (b.select(
        b.spaces,
      )..where(($SpacesTable t) => t.id.equals(spaceId))).getSingle();
      expect(removed.isArchived, isTrue);
      expect(removed.storageMode, StorageMode.local);
    },
    skip: skip,
  );
}
