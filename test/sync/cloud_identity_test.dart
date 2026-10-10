import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/sync/cloud_identity.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

/// Runs against `npx supabase start`. Set SIELTO_SUPABASE_TEST_URL and
/// SIELTO_SUPABASE_TEST_KEY to the local API URL and publishable key.
void main() {
  final String? url = Platform.environment['SIELTO_SUPABASE_TEST_URL'];
  final String? key = Platform.environment['SIELTO_SUPABASE_TEST_KEY'];
  final String? skip = url == null || key == null
      ? 'no local Supabase configured'
      : null;

  SupabaseClient client() => SupabaseClient(
    url!,
    key!,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );

  Future<CloudAccess> ensure(AppDatabase db, String userId) async {
    final CloudIdentity identity = CloudIdentity(
      db: db,
      client: client(),
      userId: userId,
    );
    addTearDown(identity.dispose);
    return identity.ensure();
  }

  late AppDatabase db;
  late String userId;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    db = inMemoryDatabase();
    userId = const Uuid().v4();
  });
  tearDown(() => db.close());

  test('a first sign-in registers the user id', () async {
    final CloudIdentity identity = CloudIdentity(
      db: db,
      client: client(),
      userId: userId,
    );
    addTearDown(identity.dispose);

    expect(await identity.ensure(), CloudAccess.ready);
    final List<Map<String, dynamic>> rows = await identity.client
        .from('user_devices')
        .select('user_id');
    expect(rows.single['user_id'], userId);
    final CloudIdentityData row = await db.select(db.cloudIdentity).getSingle();
    expect(row.registered, isTrue);
    expect(row.session, isNotNull);
  }, skip: skip);

  test('a restart reuses the stored session', () async {
    final CloudIdentity first = CloudIdentity(
      db: db,
      client: client(),
      userId: userId,
    );
    addTearDown(first.dispose);
    await first.ensure();

    final CloudIdentity second = CloudIdentity(
      db: db,
      client: client(),
      userId: userId,
    );
    addTearDown(second.dispose);
    expect(await second.ensure(), CloudAccess.ready);
    expect(
      second.client.auth.currentUser!.id,
      first.client.auth.currentUser!.id,
    );
  }, skip: skip);

  test('a lost session leaves the device unlinked', () async {
    await ensure(db, userId);
    await db
        .update(db.cloudIdentity)
        .write(const CloudIdentityCompanion(session: Value<String?>(null)));

    expect(await ensure(db, userId), CloudAccess.unlinked);
  }, skip: skip);

  test('another device cannot claim a registered user id', () async {
    await ensure(db, userId);
    final AppDatabase other = inMemoryDatabase();
    addTearDown(other.close);

    expect(await ensure(other, userId), CloudAccess.unlinked);
  }, skip: skip);
}
