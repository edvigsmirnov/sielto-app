import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/enums.dart';

/// A currency change after the Space's first record.
class CurrencyFrozen implements Exception {
  const CurrencyFrozen(this.spaceId);

  final String spaceId;

  @override
  String toString() => 'CurrencyFrozen: $spaceId';
}

/// Spaces are device rows without sync columns. Archiving is local.
class SpaceRepository {
  SpaceRepository({required this.db, required this.clock});

  final AppDatabase db;
  final SpaceClock clock;

  Future<List<Space>> all() => _selectAll().get();

  Stream<List<Space>> watchAll() => _selectAll().watch();

  Stream<List<Space>> watchArchived() =>
      (db.select(db.spaces)
            ..where(($SpacesTable t) => t.isArchived.equals(true))
            ..orderBy(<OrderClauseGenerator<$SpacesTable>>[
              ($SpacesTable t) => OrderingTerm(expression: t.createdAt),
            ]))
          .watch();

  Future<Space?> byId(String id) => _selectById(id).getSingleOrNull();

  Stream<Space?> watchById(String id) => _selectById(id).watchSingleOrNull();

  SimpleSelectStatement<$SpacesTable, Space> _selectAll() =>
      db.select(db.spaces)
        ..where(($SpacesTable t) => t.isArchived.equals(false))
        ..orderBy(<OrderClauseGenerator<$SpacesTable>>[
          ($SpacesTable t) => OrderingTerm(expression: t.createdAt),
        ]);

  SimpleSelectStatement<$SpacesTable, Space> _selectById(String id) =>
      db.select(db.spaces)..where(($SpacesTable t) => t.id.equals(id));

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
            createdAt: clock.nowUtc(),
          ),
        );
  }

  Future<int> setTitle(String spaceId, String title) =>
      (db.update(db.spaces)..where(($SpacesTable t) => t.id.equals(spaceId)))
          .write(SpacesCompanion(title: Value<String>(title.trim())));

  /// Throws [ArgumentError] on an unknown zone.
  Future<int> setTimezone(String spaceId, String timezone) {
    if (!SpaceClock.isKnownTimezone(timezone)) {
      throw ArgumentError.value(timezone, 'timezone', 'unknown IANA zone');
    }
    return (db.update(db.spaces)
          ..where(($SpacesTable t) => t.id.equals(spaceId)))
        .write(SpacesCompanion(timezone: Value<String>(timezone)));
  }

  /// True until the Space has a live payment or income.
  Future<bool> canChangeCurrency(String spaceId) async {
    final Payment? payment =
        await (db.select(db.payments)
              ..where(
                ($PaymentsTable t) =>
                    t.spaceId.equals(spaceId) & t.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();
    if (payment != null) return false;

    final Income? income =
        await (db.select(db.incomes)
              ..where(
                ($IncomesTable t) =>
                    t.spaceId.equals(spaceId) & t.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();
    return income == null;
  }

  Future<int> setCurrency(String spaceId, String currencyCode) async {
    if (!await canChangeCurrency(spaceId)) throw CurrencyFrozen(spaceId);
    return (db.update(db.spaces)
          ..where(($SpacesTable t) => t.id.equals(spaceId)))
        .write(SpacesCompanion(currencyCode: Value<String>(currencyCode)));
  }

  /// Paid expenses dated on or before the snapshot time are excluded from the
  /// walk.
  Future<int> setManualBalance(String spaceId, Decimal balance) =>
      (db.update(
        db.spaces,
      )..where(($SpacesTable t) => t.id.equals(spaceId))).write(
        SpacesCompanion(
          manualBalance: Value<Decimal?>(balance),
          manualBalanceUpdatedAt: Value<DateTime?>(clock.nowUtc()),
        ),
      );

  Future<int> setArchived(String spaceId, {required bool isArchived}) =>
      (db.update(db.spaces)..where(($SpacesTable t) => t.id.equals(spaceId)))
          .write(SpacesCompanion(isArchived: Value<bool>(isArchived)));

  Future<int> setFeedOrderMode(String spaceId, FeedOrderMode mode) =>
      (db.update(db.spaces)..where(($SpacesTable t) => t.id.equals(spaceId)))
          .write(SpacesCompanion(feedOrderMode: Value<FeedOrderMode>(mode)));

  SpaceClock clockFor(Space space) => SpaceClock(timezone: space.timezone);
}
