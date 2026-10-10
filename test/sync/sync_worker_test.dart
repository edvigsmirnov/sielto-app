import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/sync/cloud_identity.dart';
import 'package:sielto/core/sync/sync_worker.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

/// Two devices of one user against `npx supabase start`. Needs
/// SIELTO_SUPABASE_TEST_URL, _KEY and _SECRET from `npx supabase status`.
void main() {
  final String? url = Platform.environment['SIELTO_SUPABASE_TEST_URL'];
  final String? key = Platform.environment['SIELTO_SUPABASE_TEST_KEY'];
  final String? secret = Platform.environment['SIELTO_SUPABASE_TEST_SECRET'];
  final String? skip = url == null || key == null || secret == null
      ? 'no local Supabase configured'
      : null;

  SupabaseClient client() => SupabaseClient(
    url!,
    key!,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );

  late String userId;
  late AppDatabase a;
  late AppDatabase b;
  late SyncWorker syncA;
  late SyncWorker syncB;
  late String spaceId;
  late String paymentId;

  setUpAll(() {
    SpaceClock.initialize();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    if (skip != null) return;
    userId = const Uuid().v4();
    a = inMemoryDatabase();
    b = inMemoryDatabase();

    final SupabaseClient clientA = client();
    final CloudIdentity identity = CloudIdentity(
      db: a,
      client: clientA,
      userId: userId,
    );
    await identity.ensure();

    // Stands in for the device link, which is not built yet.
    final SupabaseClient clientB = client();
    await clientB.auth.signInAnonymously();
    await SupabaseClient(url!, secret!).from('user_devices').insert(
      <String, String>{
        'auth_uid': clientB.auth.currentUser!.id,
        'user_id': userId,
        'device_id': const Uuid().v4(),
      },
    );

    syncA = SyncWorker(db: a, client: clientA);
    syncB = SyncWorker(db: b, client: clientB);

    final SpaceClock clock = SpaceClock(timezone: 'UTC');
    spaceId = (await SpaceRepository(db: a, clock: clock).create(
      title: 'Home',
      spaceType: SpaceType.personal,
      budgetMode: BudgetMode.flow,
      ownerId: userId,
      timezone: 'Europe/Berlin',
      currencyCode: 'EUR',
      storageMode: StorageMode.cloud,
    )).id;
    paymentId =
        (await PaymentRepository(db: a, clock: clock, userId: userId).create(
          spaceId: spaceId,
          title: 'Rent',
          amount: Decimal.parse('1200.00'),
          dueDate: const CalendarDate(2026, 10, 1),
          expenseType: ExpenseType.mandatory,
        )).id;
    await a.customUpdate(
      'UPDATE payments SET client_edited_at = ?',
      variables: <Variable<Object>>[
        Variable<DateTime>(
          DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        ),
      ],
    );

    await syncA.syncAll();
    await syncB.syncAll();
    addTearDown(() async {
      await identity.dispose();
      await a.close();
      await b.close();
    });
  });

  Future<Payment> payment(AppDatabase db) => (db.select(
    db.payments,
  )..where(($PaymentsTable t) => t.id.equals(paymentId))).getSingle();

  Future<void> editOffline(AppDatabase db, String change, Duration ago) =>
      db.customUpdate(
        "UPDATE payments SET $change, sync_status = 'pending', "
        'client_edited_at = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<DateTime>(DateTime.now().toUtc().subtract(ago)),
          Variable<String>(paymentId),
        ],
      );

  test('a Space and its payment reach the other device', () async {
    final Space space = await (b.select(
      b.spaces,
    )..where(($SpacesTable t) => t.id.equals(spaceId))).getSingle();
    expect(space.title, 'Home');
    expect(space.storageMode, StorageMode.cloud);
    expect((await payment(b)).amount, Decimal.parse('1200.00'));
    expect((await payment(b)).syncStatus, SyncStatus.synced);
  }, skip: skip);

  for (final bool newerFirst in <bool>[true, false]) {
    test('an offline conflict settles on the later edit '
        '(${newerFirst ? 'newer' : 'older'} edit syncs first)', () async {
      await editOffline(a, "amount = '1300'", const Duration(minutes: 10));
      await editOffline(b, "amount = '1350'", const Duration(minutes: 5));

      final List<SyncWorker> order = newerFirst
          ? <SyncWorker>[syncB, syncA]
          : <SyncWorker>[syncA, syncB];
      for (final SyncWorker w in <SyncWorker>[...order, ...order]) {
        await w.syncAll();
      }

      expect((await payment(a)).amount, Decimal.parse('1350'));
      expect((await payment(b)).amount, Decimal.parse('1350'));
      expect((await payment(a)).syncStatus, SyncStatus.synced);
    }, skip: skip);
  }

  test('a later deletion beats an earlier edit', () async {
    await editOffline(b, "amount = '999'", const Duration(minutes: 5));
    await editOffline(a, 'is_deleted = 1', const Duration(minutes: 1));

    for (final SyncWorker w in <SyncWorker>[syncB, syncA, syncB, syncA]) {
      await w.syncAll();
    }

    expect((await payment(a)).isDeleted, isTrue);
    expect((await payment(b)).isDeleted, isTrue);
  }, skip: skip);

  test('a Space edit reaches the other device', () async {
    await SpaceRepository(
      db: b,
      clock: SpaceClock(timezone: 'UTC'),
    ).setManualBalance(spaceId, Decimal.parse('500'));

    await syncB.syncAll();
    await syncA.syncAll();

    final Space space = await (a.select(
      a.spaces,
    )..where(($SpacesTable t) => t.id.equals(spaceId))).getSingle();
    expect(space.manualBalance, Decimal.parse('500'));
  }, skip: skip);
}
