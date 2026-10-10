import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/sync/cloud_identity.dart';
import 'package:sielto/core/sync/device_link.dart';
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

  test('a sealed key opens only with the recipient key pair', () async {
    final SimpleKeyPair recipient = await DeviceLink.newKeyPair();
    final String sealed = await DeviceLink.seal(
      'ABCD-EFGH',
      await DeviceLink.publicKeyOf(recipient),
    );

    expect(await DeviceLink.open(sealed, recipient), 'ABCD-EFGH');
    await expectLater(
      DeviceLink.open(sealed, await DeviceLink.newKeyPair()),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test(
    'a new device joins with a code and receives the Recovery Key',
    () async {
      SupabaseClient client() => SupabaseClient(
        url!,
        key!,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      final String userId = const Uuid().v4();
      final AppDatabase a = inMemoryDatabase();
      final AppDatabase b = inMemoryDatabase();
      final SupabaseClient clientA = client();
      final SupabaseClient clientB = client();
      final CloudIdentity identityA = CloudIdentity(
        db: a,
        client: clientA,
        userId: userId,
      );
      final CloudIdentity identityB = CloudIdentity(
        db: b,
        client: clientB,
        userId: const Uuid().v4(),
      );
      addTearDown(() async {
        await identityA.dispose();
        await identityB.dispose();
        await a.close();
        await b.close();
      });

      await identityA.ensure();
      final String spaceId =
          (await SpaceRepository(
                db: a,
                clock: SpaceClock(timezone: 'UTC'),
              ).create(
                title: 'Home',
                spaceType: SpaceType.personal,
                budgetMode: BudgetMode.flow,
                ownerId: userId,
                timezone: 'UTC',
                currencyCode: 'EUR',
                storageMode: StorageMode.cloud,
              ))
              .id;
      await SyncWorker(db: a, client: clientA).syncAll();

      final String code = await clientA.rpc<String>('create_device_link_code');
      final SimpleKeyPair pair = await DeviceLink.newKeyPair();
      expect(await identityB.link('WRONG234', 'x'), isNull);
      expect(
        await identityB.link(code, await DeviceLink.publicKeyOf(pair)),
        userId,
      );

      final Future<bool> handed = DeviceLink.handOver(clientA, 'RK-1234');
      expect(await DeviceLink.receive(clientB, pair), 'RK-1234');
      expect(await handed, isTrue);

      await SyncWorker(db: b, client: clientB).syncAll();
      final Space space = await (b.select(
        b.spaces,
      )..where(($SpacesTable t) => t.id.equals(spaceId))).getSingle();
      expect(space.title, 'Home');
    },
    skip: skip,
  );
}
