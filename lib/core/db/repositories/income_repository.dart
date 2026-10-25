import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/deadline_guard.dart';
import 'package:sielto/core/db/freeze_guard.dart';
import 'package:sielto/core/db/repositories/budget_period_repository.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/schedule/income_schedule.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// Removing or demoting the last anchor of an income_driven Space that has
/// regular incomes.
class LastAnchorRequired implements Exception {
  const LastAnchorRequired(this.ruleId);

  final String ruleId;

  @override
  String toString() => 'LastAnchorRequired: $ruleId';
}

class IncomeRuleRepository
    extends
        SyncedRepository<$IncomeRecurrenceRulesTable, IncomeRecurrenceRule> {
  IncomeRuleRepository({
    required super.db,
    required super.clock,
    required super.userId,
  });

  @override
  TableInfo<$IncomeRecurrenceRulesTable, IncomeRecurrenceRule> get table =>
      db.incomeRecurrenceRules;

  Future<List<IncomeRecurrenceRule>> inSpace(String spaceId) =>
      selectAliveInSpace(spaceId).get();

  Stream<List<IncomeRecurrenceRule>> watchInSpace(String spaceId) =>
      selectAliveInSpace(spaceId).watch();

  Future<IncomeRecurrenceRule?> byId(String id) =>
      (selectAlive()..where(($IncomeRecurrenceRulesTable t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<IncomeRecurrenceRule>> anchorsInSpace(String spaceId) =>
      (selectAliveInSpace(spaceId)
            ..where(($IncomeRecurrenceRulesTable t) => t.isAnchor.equals(true)))
          .get();

  /// CHECK constraints reject schedule fields that do not match the type.
  Future<IncomeRecurrenceRule> create({
    required String spaceId,
    required String title,
    required IncomeSchedule schedule,
    Decimal? amount,
    bool isAnchor = false,
    String? countryCode,
  }) {
    final ({String author, DateTime editedAt}) s = stamp();
    return db
        .into(db.incomeRecurrenceRules)
        .insertReturning(
          _scheduleColumns(schedule).copyWith(
            id: Value<String>(SyncedRepository.newId()),
            spaceId: Value<String>(spaceId),
            title: Value<String>(title.trim()),
            amount: Value<Decimal?>(amount),
            isAnchor: Value<bool>(isAnchor),
            countryCode: Value<String?>(countryCode),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: Value<DateTime>(s.editedAt),
            createdAt: Value<DateTime>(s.editedAt),
          ),
        );
  }

  /// The schedule's type and fields; the other types' fields cleared, as the
  /// table requires.
  static IncomeRecurrenceRulesCompanion _scheduleColumns(
    IncomeSchedule schedule,
  ) {
    return IncomeRecurrenceRulesCompanion(
      scheduleType: Value<ScheduleType>(switch (schedule) {
        FixedDateSchedule() => ScheduleType.fixedDate,
        WeekdayRuleSchedule() => ScheduleType.weekdayRule,
        DateRangeSchedule() => ScheduleType.dateRange,
        BoundaryDaysSchedule() => ScheduleType.boundaryDays,
      }),
      fixedDay: Value<int?>(
        schedule is FixedDateSchedule ? schedule.day : null,
      ),
      weekdayOrdinal: Value<WeekdayOrdinal?>(
        schedule is WeekdayRuleSchedule ? schedule.ordinal : null,
      ),
      weekdayDay: Value<Weekday?>(
        schedule is WeekdayRuleSchedule ? schedule.weekday : null,
      ),
      dateRangeStart: Value<int?>(
        schedule is DateRangeSchedule ? schedule.startDay : null,
      ),
      dateRangeEnd: Value<int?>(
        schedule is DateRangeSchedule ? schedule.endDay : null,
      ),
      boundaryAnchor: Value<BoundaryAnchor?>(
        schedule is BoundaryDaysSchedule ? schedule.anchor : null,
      ),
      boundaryCount: Value<int?>(
        schedule is BoundaryDaysSchedule ? schedule.count : null,
      ),
    );
  }

  /// Writes every schedule field, clearing the unused ones. Existing occurrences
  /// are left to the caller.
  Future<int> updateRule(
    String ruleId, {
    required String title,
    required IncomeSchedule schedule,
    Decimal? amount,
  }) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.incomeRecurrenceRules,
    )..where(($IncomeRecurrenceRulesTable t) => t.id.equals(ruleId))).write(
      _scheduleColumns(schedule).copyWith(
        title: Value<String>(title.trim()),
        amount: Value<Decimal?>(amount),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  /// The first regular income of an income_driven Space becomes the anchor.
  Future<IncomeRecurrenceRule> createFirstAsAnchor({
    required String spaceId,
    required BudgetMode mode,
    required String title,
    required IncomeSchedule schedule,
    Decimal? amount,
    String? countryCode,
  }) async {
    final bool anchor =
        mode == BudgetMode.incomeDriven &&
        (await anchorsInSpace(spaceId)).isEmpty;
    return create(
      spaceId: spaceId,
      title: title,
      schedule: schedule,
      amount: amount,
      isAnchor: anchor,
      countryCode: countryCode,
    );
  }

  /// Applies to occurrences materialised from now on. See
  /// [IncomeRepository.updateFutureAmounts].
  Future<int> setAmount(String ruleId, Decimal? amount) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.incomeRecurrenceRules,
    )..where(($IncomeRecurrenceRulesTable t) => t.id.equals(ruleId))).write(
      IncomeRecurrenceRulesCompanion(
        amount: Value<Decimal?>(amount),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  /// Throws [LastAnchorRequired] on demoting the last anchor.
  Future<int> setAnchor(
    String ruleId, {
    required bool isAnchor,
    required BudgetMode mode,
  }) async {
    if (!isAnchor) await _refuseIfLastAnchor(ruleId, mode);
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.incomeRecurrenceRules,
    )..where(($IncomeRecurrenceRulesTable t) => t.id.equals(ruleId))).write(
      IncomeRecurrenceRulesCompanion(
        isAnchor: Value<bool>(isAnchor),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  /// Throws [LastAnchorRequired] on deleting the last anchor.
  /// Its unreceived dates from [today] on go with it; received money and
  /// past dates stay.
  Future<int> deleteRule(
    String ruleId, {
    required BudgetMode mode,
    required CalendarDate today,
  }) async {
    await _refuseIfLastAnchor(ruleId, mode);
    return db.transaction(() async {
      final ({String author, DateTime editedAt}) s = stamp();
      await (db.update(db.incomes)..where(
            ($IncomesTable t) =>
                t.recurrenceRuleId.equals(ruleId) &
                t.isPaid.equals(false) &
                t.isDeleted.equals(false) &
                t.expectedDate.isBiggerOrEqualValue(today.toIso()),
          ))
          .write(
            IncomesCompanion(
              isDeleted: const Value<bool>(true),
              syncStatus: const Value<SyncStatus>(SyncStatus.pending),
              clientEditedAt: Value<DateTime>(s.editedAt),
              lastModifiedBy: Value<String>(s.author),
            ),
          );
      return softDelete(ruleId);
    });
  }

  Future<void> _refuseIfLastAnchor(String ruleId, BudgetMode mode) async {
    if (mode != BudgetMode.incomeDriven) return;

    final IncomeRecurrenceRule? rule =
        await (selectAlive()
              ..where(($IncomeRecurrenceRulesTable t) => t.id.equals(ruleId)))
            .getSingleOrNull();
    if (rule == null || !rule.isAnchor) return;

    final List<IncomeRecurrenceRule> anchors = await anchorsInSpace(
      rule.spaceId,
    );
    if (anchors.length <= 1) throw LastAnchorRequired(ruleId);
  }
}

/// One row per expected or received income, regular and one-off.
class IncomeRepository extends SyncedRepository<$IncomesTable, Income> {
  IncomeRepository({
    required super.db,
    required super.clock,
    required super.userId,
  });

  @override
  TableInfo<$IncomesTable, Income> get table => db.incomes;

  late final FreezeGuard _freeze = FreezeGuard(db: db, clock: clock);
  late final DeadlineGuard _deadline = DeadlineGuard(
    periods: BudgetPeriodRepository(db: db, clock: clock, userId: userId),
  );

  Future<Income?> byId(String id) =>
      (selectAlive()..where(($IncomesTable t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Deleted rows included.
  Future<FreezeState> freezeStateOf(Income row) =>
      _freeze.stateOf(row.budgetPeriodId);

  @override
  Future<int> softDelete(String id) async {
    final Income? row = await byId(id);
    await _freeze.refuseIfFrozen(row?.budgetPeriodId);
    return super.softDelete(id);
  }

  Future<List<Income>> inSpace(String spaceId) => _selectInSpace(spaceId).get();

  Stream<List<Income>> watchInSpace(String spaceId) =>
      _selectInSpace(spaceId).watch();

  SimpleSelectStatement<$IncomesTable, Income> _selectInSpace(String spaceId) =>
      selectAliveInSpace(spaceId)
        ..orderBy(<OrderClauseGenerator<$IncomesTable>>[
          ($IncomesTable t) => OrderingTerm(expression: t.expectedDate),
          ($IncomesTable t) => OrderingTerm(expression: t.sortOrder),
          ($IncomesTable t) => OrderingTerm(expression: t.id),
        ]);

  Stream<List<Income>> watchOnDay(String spaceId, CalendarDate day) =>
      (_selectInSpace(spaceId)
            ..where(($IncomesTable t) => t.expectedDate.equals(day.toIso())))
          .watch();

  Future<List<Income>> forRule(String ruleId) =>
      (selectAlive()
            ..where(($IncomesTable t) => t.recurrenceRuleId.equals(ruleId)))
          .get();

  Future<Income> create({
    required String spaceId,
    required String title,
    required CalendarDate expectedDate,
    Decimal? amount,
    String? recurrenceRuleId,
    String? budgetPeriodId,
    String? notes,
    bool isPaid = false,
    String? id,
    bool generated = false,
  }) async {
    await _deadline.refuseIfBeyondDeadline(spaceId, expectedDate);

    final ({String author, DateTime editedAt}) s = stamp();
    return db
        .into(db.incomes)
        .insertReturning(
          IncomesCompanion.insert(
            id: id ?? SyncedRepository.newId(),
            spaceId: spaceId,
            title: title.trim(),
            expectedDate: expectedDate,
            amount: Value<Decimal?>(amount),
            recurrenceRuleId: Value<String?>(recurrenceRuleId),
            budgetPeriodId: Value<String?>(budgetPeriodId),
            notes: Value<String?>(notes),
            isPaid: Value<bool>(isPaid),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: generated ? SyncedRepository.generated : s.editedAt,
            createdAt: s.editedAt,
          ),
        );
  }

  Future<int> update(
    String id, {
    Value<String> title = const Value<String>.absent(),
    Value<Decimal?> amount = const Value<Decimal?>.absent(),
    Value<CalendarDate> expectedDate = const Value<CalendarDate>.absent(),
    Value<CalendarDate?> actualDate = const Value<CalendarDate?>.absent(),
    Value<String?> notes = const Value<String?>.absent(),
    Value<bool> isPaid = const Value<bool>.absent(),
  }) async {
    // A frozen period protects amount, dates and the receipt flag.
    if (amount.present ||
        expectedDate.present ||
        actualDate.present ||
        isPaid.present) {
      final Income? row = await byId(id);
      await _freeze.refuseIfFrozen(row?.budgetPeriodId);
      if (expectedDate.present && row != null) {
        await _deadline.refuseIfBeyondDeadline(row.spaceId, expectedDate.value);
      }
    }

    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.incomes,
    )..where(($IncomesTable t) => t.id.equals(id))).write(
      IncomesCompanion(
        title: title.present
            ? Value<String>(title.value.trim())
            : const Value<String>.absent(),
        amount: amount,
        expectedDate: expectedDate,
        actualDate: actualDate,
        notes: notes,
        isPaid: isPaid,
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  /// Includes deleted rows.
  Future<List<Income>> occurrencesOf(String ruleId) => (db.select(
    db.incomes,
  )..where(($IncomesTable t) => t.recurrenceRuleId.equals(ruleId))).get();

  Future<int> setPeriod(String id, String? periodId) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.incomes,
    )..where(($IncomesTable t) => t.id.equals(id))).write(
      IncomesCompanion(
        budgetPeriodId: Value<String?>(periodId),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  /// Unreceived occurrences dated [from] or later, outside frozen periods.
  Future<int> updateFutureAmounts(
    String ruleId,
    Decimal? amount, {
    required CalendarDate from,
  }) async {
    final List<Income> rows =
        await (selectAlive()..where(
              ($IncomesTable t) =>
                  t.recurrenceRuleId.equals(ruleId) &
                  t.isPaid.equals(false) &
                  t.expectedDate.isBiggerOrEqualValue(from.toIso()),
            ))
            .get();
    final List<String> ids = <String>[
      for (final Income row in rows)
        if (await _freeze.stateOf(row.budgetPeriodId) != FreezeState.frozen)
          row.id,
    ];
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.incomes,
    )..where(($IncomesTable t) => t.id.isIn(ids))).write(
      IncomesCompanion(
        amount: Value<Decimal?>(amount),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  Future<int> setSortOrder(String id, int sortOrder) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.incomes,
    )..where(($IncomesTable t) => t.id.equals(id))).write(
      IncomesCompanion(
        sortOrder: Value<int>(sortOrder),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  /// An amount is required when the row has none.
  Future<int> markReceived(
    String id, {
    Decimal? amount,
    CalendarDate? actualDate,
  }) async {
    final Income? row =
        await (selectAlive()..where(($IncomesTable t) => t.id.equals(id)))
            .getSingleOrNull();
    if (row == null) return 0;
    if (row.amount == null && amount == null) {
      throw ArgumentError.value(
        amount,
        'amount',
        'an income with no amount needs one to be marked received',
      );
    }
    return update(
      id,
      isPaid: const Value<bool>(true),
      amount: amount == null
          ? const Value<Decimal?>.absent()
          : Value<Decimal?>(amount),
      actualDate: actualDate == null
          ? const Value<CalendarDate?>.absent()
          : Value<CalendarDate?>(actualDate),
    );
  }
}
