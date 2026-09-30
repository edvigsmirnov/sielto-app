import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/app/startup.dart';
import 'package:sielto/core/backup/backup_file.dart';
import 'package:sielto/core/backup/backup_service.dart';
import 'package:sielto/core/crypto/kdf.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/category_repository.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/db/repositories/space_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

void main() {
  late AppDatabase source;
  late AppDatabase target;
  late SpaceClock clock;
  late Space space;

  setUpAll(() {
    SpaceClock.initialize();
    Kdf.cheap = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    source = inMemoryDatabase();
    target = inMemoryDatabase();
    clock = SpaceClock(
      timezone: 'Europe/Berlin',
      now: () => DateTime.utc(2026, 9, 30, 12),
    );
    space = await SpaceRepository(db: source, clock: clock).create(
      title: 'Household',
      spaceType: SpaceType.family,
      budgetMode: BudgetMode.flow,
      ownerId: 'old-user',
      timezone: 'Europe/Berlin',
      currencyCode: 'EUR',
    );
    final PaymentRepository payments = PaymentRepository(
      db: source,
      clock: clock,
      userId: 'old-user',
    );
    final Category food = await CategoryRepository(
      db: source,
      clock: clock,
      userId: 'old-user',
      payments: payments,
    ).create(spaceId: space.id, title: 'Groceries');
    await payments.create(
      spaceId: space.id,
      title: 'Rewe',
      amount: Decimal.parse('12.50'),
      dueDate: const CalendarDate(2026, 9, 29),
      expenseType: ExpenseType.variable,
      categoryId: food.id,
    );
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  BackupService service(AppDatabase db) =>
      BackupService(db: db, clock: clock, userId: 'new-user');

  Future<BackupContents> roundTrip() async {
    final Uint8List file = await BackupFile.seal(
      await BackupService(
        db: source,
        clock: clock,
        userId: 'old-user',
      ).export(),
      'correct horse',
    );
    expect(BackupFile.looksLikeBackup(file), isTrue);
    return BackupContents(await BackupFile.open(file, 'correct horse'));
  }

  test('a wrong key and a stranger file are told apart', () async {
    final Uint8List file = await BackupFile.seal(
      await service(source).export(),
      'correct horse',
    );
    await expectLater(
      BackupFile.open(file, 'wrong horse'),
      throwsA(
        isA<BackupFileException>().having(
          (BackupFileException e) => e.problem,
          'problem',
          BackupFileProblem.wrongKey,
        ),
      ),
    );
    await expectLater(
      BackupFile.open(Uint8List(200), 'correct horse'),
      throwsA(
        isA<BackupFileException>().having(
          (BackupFileException e) => e.problem,
          'problem',
          BackupFileProblem.notABackup,
        ),
      ),
    );
  });

  test('restores every row on an empty device, owned by its user', () async {
    final BackupContents backup = await roundTrip();
    await service(target).restore(backup, const <String, RestoreChoice>{});

    final List<Space> spaces = await target.select(target.spaces).get();
    expect(spaces.single.id, space.id);
    expect(spaces.single.ownerId, 'new-user');
    final Payment payment = await target.select(target.payments).getSingle();
    expect(payment.amount, Decimal.parse('12.50'));
    expect(payment.lastModifiedBy, 'new-user');
    expect(
      payment.categoryId,
      (await target.select(target.categories).getSingle()).id,
    );
  });

  test('replace, copy and skip for a Space that already exists', () async {
    final BackupContents backup = await roundTrip();
    await service(target).restore(backup, const <String, RestoreChoice>{});
    expect(await service(target).conflicts(backup), <String>{space.id});

    await service(target).restore(backup, const <String, RestoreChoice>{});
    expect(await target.select(target.payments).get(), hasLength(1));

    await service(
      target,
    ).restore(backup, <String, RestoreChoice>{space.id: RestoreChoice.replace});
    expect(await target.select(target.spaces).get(), hasLength(1));
    expect(await target.select(target.payments).get(), hasLength(1));

    await service(target)
        .restore(backup, <String, RestoreChoice>{space.id: RestoreChoice.copy});
    final List<Space> spaces = await target.select(target.spaces).get();
    expect(spaces, hasLength(2));
    final Space copy = spaces.firstWhere((Space s) => s.id != space.id);
    expect(copy.title, 'Household (copy)');
    final String copyId = copy.id;
    final List<Payment> payments = await target.select(target.payments).get();
    expect(payments, hasLength(2));
    final Payment copied = payments.firstWhere(
      (Payment p) => p.spaceId == copyId,
    );
    final Category copiedCategory = await (target.select(
      target.categories,
    )..where(($CategoriesTable c) => c.spaceId.equals(copyId))).getSingle();
    expect(copied.categoryId, copiedCategory.id);
  });
}
