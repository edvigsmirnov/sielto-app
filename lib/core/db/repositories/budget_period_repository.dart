import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

class BudgetPeriodRepository
    extends SyncedRepository<$BudgetPeriodsTable, BudgetPeriod> {
  BudgetPeriodRepository({
    required super.db,
    required super.clock,
    required super.userId,
  });

  @override
  TableInfo<$BudgetPeriodsTable, BudgetPeriod> get table => db.budgetPeriods;

  Future<List<BudgetPeriod>> inSpace(String spaceId) => _byStart(spaceId).get();

  Stream<List<BudgetPeriod>> watchInSpace(String spaceId) =>
      _byStart(spaceId).watch();

  SimpleSelectStatement<$BudgetPeriodsTable, BudgetPeriod> _byStart(
    String spaceId,
  ) => selectAliveInSpace(spaceId)
    ..orderBy(<OrderClauseGenerator<$BudgetPeriodsTable>>[
      ($BudgetPeriodsTable t) => OrderingTerm(expression: t.startDate),
    ]);

  /// The single `continuous` row of a Flow or Budget Space.
  Future<BudgetPeriod?> continuousFor(String spaceId) =>
      (selectAliveInSpace(spaceId)..where(
            ($BudgetPeriodsTable t) =>
                t.periodType.equalsValue(PeriodType.continuous),
          ))
          .getSingleOrNull();

  /// Idempotent.
  Future<BudgetPeriod> ensureContinuous({
    required String spaceId,
    required CalendarDate startDate,
    Decimal? budgetTarget,
    CalendarDate? deadlineDate,
    bool deadlineIsHard = false,
  }) async {
    final BudgetPeriod? existing = await continuousFor(spaceId);
    if (existing != null) return existing;

    final ({String author, DateTime editedAt}) s = stamp();
    return db
        .into(db.budgetPeriods)
        .insertReturning(
          BudgetPeriodsCompanion.insert(
            id: SyncedRepository.newId(),
            spaceId: spaceId,
            periodType: PeriodType.continuous,
            startDate: startDate,
            budgetTarget: Value<Decimal?>(budgetTarget),
            deadlineDate: Value<CalendarDate?>(deadlineDate),
            deadlineIsHard: Value<bool>(deadlineIsHard),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: s.editedAt,
            createdAt: s.editedAt,
          ),
        );
  }

  /// Boundaries are inclusive: `[anchor, next anchor - 1]`.
  Future<BudgetPeriod> createIncomeDriven({
    required String spaceId,
    required CalendarDate startDate,
    required CalendarDate endDate,
    required CalendarDate anchorDate,
    CalendarDate? windowStart,
    CalendarDate? windowEnd,
    bool holidayDataIncomplete = false,
  }) {
    final ({String author, DateTime editedAt}) s = stamp();
    return db
        .into(db.budgetPeriods)
        .insertReturning(
          BudgetPeriodsCompanion.insert(
            id: SyncedRepository.newId(),
            spaceId: spaceId,
            periodType: PeriodType.incomeDriven,
            startDate: startDate,
            endDate: Value<CalendarDate?>(endDate),
            anchorDate: Value<CalendarDate?>(anchorDate),
            windowStart: Value<CalendarDate?>(windowStart),
            windowEnd: Value<CalendarDate?>(windowEnd),
            holidayDataIncomplete: Value<bool>(holidayDataIncomplete),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: s.editedAt,
            createdAt: s.editedAt,
          ),
        );
  }

  /// Oldest first.
  Future<List<BudgetPeriod>> incomeDrivenIn(String spaceId) =>
      (_byStart(spaceId)..where(
            ($BudgetPeriodsTable t) =>
                t.periodType.equalsValue(PeriodType.incomeDriven),
          ))
          .get();

  /// Updates in place: payments pinned by hand keep their period.
  Future<int> updateBoundaries(
    String periodId, {
    required CalendarDate startDate,
    required CalendarDate? endDate,
    required CalendarDate anchorDate,
    required CalendarDate windowStart,
    required CalendarDate windowEnd,
    bool holidayDataIncomplete = false,
  }) => _write(
    periodId,
    BudgetPeriodsCompanion(
      startDate: Value<CalendarDate>(startDate),
      endDate: Value<CalendarDate?>(endDate),
      anchorDate: Value<CalendarDate?>(anchorDate),
      windowStart: Value<CalendarDate?>(windowStart),
      windowEnd: Value<CalendarDate?>(windowEnd),
      holidayDataIncomplete: Value<bool>(holidayDataIncomplete),
    ),
  );

  Future<BudgetPeriod?> containing(String spaceId, CalendarDate date) async {
    final List<BudgetPeriod> periods = await inSpace(spaceId);
    for (final BudgetPeriod p in periods) {
      if (p.startDate.isAfter(date)) continue;
      final CalendarDate? end = p.endDate;
      if (end == null || !end.isBefore(date)) return p;
    }
    return null;
  }

  /// Null clears the fund target.
  Future<int> setBudgetTarget(String periodId, Decimal? target) => _write(
    periodId,
    BudgetPeriodsCompanion(budgetTarget: Value<Decimal?>(target)),
  );

  /// Records past a moved deadline are marked, never deleted.
  Future<int> setDeadline(
    String periodId, {
    required CalendarDate? date,
    required bool isHard,
  }) => _write(
    periodId,
    BudgetPeriodsCompanion(
      deadlineDate: Value<CalendarDate?>(date),
      deadlineIsHard: Value<bool>(date != null && isHard),
    ),
  );

  Future<int> _write(String periodId, BudgetPeriodsCompanion values) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.budgetPeriods,
    )..where(($BudgetPeriodsTable t) => t.id.equals(periodId))).write(
      values.copyWith(
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  Future<int> unfreeze(String periodId, DateTime until, String reason) =>
      _write(
        periodId,
        BudgetPeriodsCompanion(
          unfrozenUntil: Value<DateTime?>(until),
          unfreezeReason: Value<String?>(reason),
        ),
      );
}
