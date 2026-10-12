import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/enums.dart';

/// Shared fields sync by last write; archiving is local.
class SpaceRepository {
  SpaceRepository({required this.db, required this.clock});

  final AppDatabase db;
  final SpaceClock clock;

  Stream<List<Space>> watchAll() => _byCreation(archived: false).watch();

  Stream<List<Space>> watchArchived() => _byCreation(archived: true).watch();

  Future<Space?> byId(String id) => (db.select(
    db.spaces,
  )..where(($SpacesTable t) => t.id.equals(id))).getSingleOrNull();

  SimpleSelectStatement<$SpacesTable, Space> _byCreation({
    required bool archived,
  }) => db.select(db.spaces)
    ..where(($SpacesTable t) => t.isArchived.equals(archived))
    ..orderBy(<OrderClauseGenerator<$SpacesTable>>[
      ($SpacesTable t) => OrderingTerm(expression: t.createdAt),
    ]);

  Future<Space> create({
    required String title,
    required SpaceType spaceType,
    required BudgetMode budgetMode,
    required String ownerId,
    required String timezone,
    required String currencyCode,
    StorageMode storageMode = StorageMode.local,
    String? countryCode,
  }) {
    if (!SpaceClock.isKnownTimezone(timezone)) {
      throw ArgumentError.value(timezone, 'timezone', 'unknown IANA zone');
    }
    final DateTime now = clock.nowUtc();
    return db
        .into(db.spaces)
        .insertReturning(
          SpacesCompanion.insert(
            id: SyncedRepository.newId(),
            title: title.trim(),
            spaceType: spaceType,
            budgetMode: budgetMode,
            ownerId: ownerId,
            storageMode: storageMode,
            timezone: timezone,
            currencyCode: currencyCode,
            countryCode: Value<String?>(countryCode),
            createdAt: now,
            clientEditedAt: Value<DateTime?>(now),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
          ),
        );
  }

  Future<int> setTitle(String spaceId, String title) =>
      _edit(spaceId, SpacesCompanion(title: Value<String>(title.trim())));

  /// Throws [ArgumentError] on an unknown zone.
  Future<int> setTimezone(String spaceId, String timezone) {
    if (!SpaceClock.isKnownTimezone(timezone)) {
      throw ArgumentError.value(timezone, 'timezone', 'unknown IANA zone');
    }
    return _edit(spaceId, SpacesCompanion(timezone: Value<String>(timezone)));
  }

  /// Only the label changes: amounts are kept as they are, never converted.
  Future<int> setCurrency(String spaceId, String currencyCode) => _edit(
    spaceId,
    SpacesCompanion(currencyCode: Value<String>(currencyCode)),
  );

  /// Paid expenses dated on or before the snapshot time are excluded from the
  /// walk.
  Future<int> setManualBalance(String spaceId, Decimal balance) => _edit(
    spaceId,
    SpacesCompanion(
      manualBalance: Value<Decimal?>(balance),
      manualBalanceUpdatedAt: Value<DateTime?>(clock.nowUtc()),
    ),
  );

  Future<int> setArchived(String spaceId, {required bool isArchived}) =>
      (db.update(db.spaces)..where(($SpacesTable t) => t.id.equals(spaceId)))
          .write(SpacesCompanion(isArchived: Value<bool>(isArchived)));

  /// Hard delete of the Space and every row that belongs to it.
  Future<void> deleteForever(String spaceId) => db.transaction(() async {
    await (db.delete(
      db.payments,
    )..where(($PaymentsTable t) => t.spaceId.equals(spaceId))).go();
    await (db.delete(
      db.incomes,
    )..where(($IncomesTable t) => t.spaceId.equals(spaceId))).go();
    await (db.delete(db.incomeRecurrenceRules)
          ..where(($IncomeRecurrenceRulesTable t) => t.spaceId.equals(spaceId)))
        .go();
    await (db.delete(
      db.budgetPeriods,
    )..where(($BudgetPeriodsTable t) => t.spaceId.equals(spaceId))).go();
    await (db.delete(
      db.categories,
    )..where(($CategoriesTable t) => t.spaceId.equals(spaceId))).go();
    await (db.delete(
      db.memberLocalLabels,
    )..where(($MemberLocalLabelsTable t) => t.spaceId.equals(spaceId))).go();
    await (db.delete(
      db.spaceMembers,
    )..where(($SpaceMembersTable t) => t.spaceId.equals(spaceId))).go();
    await (db.delete(
      db.spaces,
    )..where(($SpacesTable t) => t.id.equals(spaceId))).go();
  });

  Future<int> setFeedOrderMode(String spaceId, FeedOrderMode mode) => _edit(
    spaceId,
    SpacesCompanion(feedOrderMode: Value<FeedOrderMode>(mode)),
  );

  /// A shared Space kept after it left the cloud becomes this user's own.
  Future<int> keepAsOwn(String spaceId, String ownerId) =>
      (db.update(
        db.spaces,
      )..where(($SpacesTable t) => t.id.equals(spaceId))).write(
        SpacesCompanion(
          ownerId: Value<String>(ownerId),
          isArchived: const Value<bool>(false),
        ),
      );

  /// Null means no limit.
  Future<int> setMaxMembers(String spaceId, int? max) =>
      _edit(spaceId, SpacesCompanion(maxMembers: Value<int?>(max)));

  Future<int> _edit(String spaceId, SpacesCompanion change) =>
      (db.update(
        db.spaces,
      )..where(($SpacesTable t) => t.id.equals(spaceId))).write(
        change.copyWith(
          clientEditedAt: Value<DateTime?>(clock.nowUtc()),
          syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        ),
      );

  SpaceClock clockFor(Space space) => clock.inZone(space.timezone);
}
