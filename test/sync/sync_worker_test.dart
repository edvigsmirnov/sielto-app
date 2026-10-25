import 'dart:async';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/budget_period_repository.dart';
import 'package:sielto/core/db/repositories/income_repository.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/sync/cloud_identity.dart';
import 'package:sielto/core/sync/sync_worker.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/schedule/income_schedule.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/periods/period_service.dart';
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
  late SupabaseClient clientA;

  setUpAll(() {
    SpaceClock.initialize();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    if (skip != null) return;
    userId = const Uuid().v4();
    a = inMemoryDatabase();
    b = inMemoryDatabase();

    clientA = client();
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

  for (final bool generatedFirst in <bool>[true, false]) {
    test(
      'a date both devices fill in becomes one row and keeps the edit '
      '(${generatedFirst ? 'untouched' : 'edited'} copy syncs first)',
      () async {
        final SpaceClock clock = SpaceClock(timezone: 'UTC');
        final String ruleId =
            (await IncomeRuleRepository(
                  db: a,
                  clock: clock,
                  userId: userId,
                ).create(
                  spaceId: spaceId,
                  title: 'Salary',
                  schedule: FixedDateSchedule(1),
                  amount: Decimal.parse('3000'),
                ))
                .id;
        await syncA.syncAll();
        await syncB.syncAll();

        Future<Income> fillIn(AppDatabase db) =>
            IncomeRepository(db: db, clock: clock, userId: userId).create(
              spaceId: spaceId,
              title: 'Salary',
              expectedDate: const CalendarDate(2026, 11, 1),
              amount: Decimal.parse('3000'),
              recurrenceRuleId: ruleId,
              id: incomeSlotId(ruleId, 2026, 11),
              generated: true,
            );
        final Income onA = await fillIn(a);
        await IncomeRepository(
          db: a,
          clock: clock,
          userId: userId,
        ).update(onA.id, amount: Value<Decimal?>(Decimal.parse('3100')));
        await fillIn(b);

        final List<SyncWorker> order = generatedFirst
            ? <SyncWorker>[syncB, syncA]
            : <SyncWorker>[syncA, syncB];
        for (final SyncWorker w in <SyncWorker>[...order, ...order]) {
          await w.syncAll();
        }

        for (final AppDatabase db in <AppDatabase>[a, b]) {
          final List<Income> rows = await db.select(db.incomes).get();
          expect(rows.single.id, onA.id);
          expect(rows.single.amount, Decimal.parse('3100'));
        }
      },
      skip: skip,
    );
  }

  test('periods and income dates both devices work out are not '
      'duplicated', () async {
    final DateTime now = DateTime.now().toUtc();
    final CalendarDate today = CalendarDate(now.year, now.month, now.day);
    final SpaceClock clock = SpaceClock(timezone: 'UTC');
    Repositories repos(AppDatabase db) =>
        Repositories(db: db, clock: clock, userId: userId);
    PeriodService service(AppDatabase db) => PeriodService(
      repos: repos(db),
      calendar: WorkingDayCalendar.weekendsOnly(),
    );

    final Space space = await repos(a).spaces.create(
      title: 'Salary',
      spaceType: SpaceType.personal,
      budgetMode: BudgetMode.incomeDriven,
      ownerId: userId,
      timezone: 'UTC',
      currencyCode: 'EUR',
      storageMode: StorageMode.cloud,
    );
    await repos(a).incomeRules.create(
      spaceId: space.id,
      title: 'Salary',
      schedule: FixedDateSchedule(26),
      amount: Decimal.parse('3000'),
      isAnchor: true,
    );
    await syncA.syncAll();
    await syncB.syncAll();

    Future<Set<String>> ids(AppDatabase db, String table) async => <String>{
      for (final QueryRow r
          in await db
              .customSelect(
                'SELECT id FROM $table WHERE space_id = ? AND is_deleted = 0',
                variables: <Variable<Object>>[Variable<String>(space.id)],
              )
              .get())
        r.read<String>('id'),
    };
    await service(a).refresh(space, today);
    final Map<String, Set<String>> alone = <String, Set<String>>{
      for (final String table in <String>['budget_periods', 'incomes'])
        table: await ids(a, table),
    };
    await service(b).refresh(space, today);
    for (final SyncWorker w in <SyncWorker>[syncA, syncB, syncA, syncB]) {
      await w.syncAll();
    }

    for (final String table in <String>['budget_periods', 'incomes']) {
      expect(alone[table], isNotEmpty);
      expect(await ids(a, table), alone[table], reason: table);
      expect(await ids(b, table), alone[table], reason: table);
    }
  }, skip: skip);

  test('an edit the server refuses as frozen is kept and not resent', () async {
    final SpaceClock clock = SpaceClock(timezone: 'UTC');
    final BudgetPeriod closed =
        await BudgetPeriodRepository(
          db: a,
          clock: clock,
          userId: userId,
        ).createIncomeDriven(
          spaceId: spaceId,
          startDate: const CalendarDate(2026, 1, 1),
          endDate: const CalendarDate(2026, 1, 31),
          anchorDate: const CalendarDate(2026, 1, 1),
        );
    final String frozenId =
        (await PaymentRepository(db: a, clock: clock, userId: userId).create(
          spaceId: spaceId,
          budgetPeriodId: closed.id,
          title: 'Groceries',
          amount: Decimal.parse('80'),
          dueDate: const CalendarDate(2026, 1, 20),
          expenseType: ExpenseType.variable,
        )).id;
    await syncA.syncAll();
    await syncB.syncAll();

    await a.customUpdate(
      "UPDATE payments SET amount = '95', sync_status = 'pending', "
      'client_edited_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<String>(frozenId),
      ],
    );
    await syncA.syncAll();
    expect(syncA.changes.single.conflict, ConflictKind.refused);
    await syncA.syncAll();
    await syncB.syncAll();

    Future<Payment> row(AppDatabase db) => (db.select(
      db.payments,
    )..where(($PaymentsTable t) => t.id.equals(frozenId))).getSingle();
    expect((await row(a)).syncStatus, SyncStatus.rejected);
    expect((await row(a)).amount, Decimal.parse('95'));
    expect((await row(b)).amount, Decimal.parse('80'));

    // Kept as a note: the shared amount returns and the note reaches B.
    await syncA.takeServer(
      'payments',
      frozenId,
      note: 'was 95',
      on: const CalendarDate(2026, 10, 11),
    );
    await syncA.syncAll();
    await syncB.syncAll();
    expect((await row(a)).amount, Decimal.parse('80'));
    expect((await row(a)).syncStatus, SyncStatus.synced);
    expect((await row(b)).notes, contains('was 95'));

    // A refused deletion is undone at once.
    await a.customUpdate(
      "UPDATE payments SET is_deleted = 1, sync_status = 'pending', "
      'client_edited_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<String>(frozenId),
      ],
    );
    await syncA.syncAll();
    expect(syncA.changes.single.conflict, ConflictKind.refusedDeletion);
    expect((await row(a)).isDeleted, isFalse);
    expect((await row(a)).syncStatus, SyncStatus.synced);
  }, skip: skip);

  test('a Space taken off the server becomes an archive elsewhere', () async {
    await clientA.from('spaces').delete().eq('id', spaceId);
    await a.customUpdate(
      "UPDATE spaces SET storage_mode = 'local', sync_status = 'none', "
      'server_received_at = NULL, synced_until = NULL WHERE id = ?',
      variables: <Variable<Object>>[Variable<String>(spaceId)],
    );

    await syncA.syncAll();
    await syncB.syncAll();

    final Space onB = await (b.select(
      b.spaces,
    )..where(($SpacesTable t) => t.id.equals(spaceId))).getSingle();
    expect(onB.isArchived, isTrue);
    expect(onB.storageMode, StorageMode.local);
    expect(await clientA.from('spaces').select('id'), isEmpty);
  }, skip: skip);

  test('the other device hears about a change at once', () async {
    final Completer<void> heard = Completer<void>();
    final RealtimeChannel channel = syncB.watchRemote(() {
      if (!heard.isCompleted) heard.complete();
    });
    addTearDown(() => syncB.client.removeChannel(channel));

    // Edits until heard: the subscription joins on its own time.
    for (int i = 0; i < 10 && !heard.isCompleted; i++) {
      await editOffline(a, "amount = '${1250 + i}'", Duration.zero);
      await syncA.syncAll();
      await Future.any(<Future<void>>[
        heard.future,
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
    }
    expect(heard.isCompleted, isTrue);
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

  group('changes by someone else', () {
    // Device B's edits carry an author this worker does not know.
    late SyncWorker watcher;
    setUp(() {
      if (skip != null) return;
      watcher = SyncWorker(db: a, client: clientA, userId: const Uuid().v4());
    });

    test('are reported once, with what changed', () async {
      await editOffline(b, "amount = '900'", Duration.zero);
      await syncB.syncAll();
      await watcher.syncAll();

      final RemoteChange change = watcher.changes.single;
      expect(change.kind, ChangeKind.edited);
      expect(change.title, 'Rent');
      expect(change.amount, Decimal.parse('900'));
      expect(change.author, userId);
      expect(change.conflict, isNull);

      await watcher.syncAll();
      expect(watcher.changes, isEmpty);
    }, skip: skip);

    test('a later edit over this one is a conflict', () async {
      await editOffline(a, "amount = '1300'", const Duration(minutes: 10));
      await editOffline(b, "amount = '1350'", const Duration(minutes: 5));
      await syncB.syncAll();
      await watcher.syncAll();

      final RemoteChange change = watcher.changes.single;
      expect(change.conflict, ConflictKind.overwritten);
      expect(change.mine!.isBefore(change.theirs), isTrue);
    }, skip: skip);

    test('a later deletion over this edit says so', () async {
      await editOffline(a, "amount = '1300'", const Duration(minutes: 10));
      await editOffline(b, 'is_deleted = 1', const Duration(minutes: 5));
      await syncB.syncAll();
      await watcher.syncAll();

      expect(watcher.changes.single.kind, ChangeKind.deleted);
      expect(watcher.changes.single.conflict, ConflictKind.deletedOverEdit);
    }, skip: skip);
  });
}
