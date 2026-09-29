import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/deadline_guard.dart';
import 'package:sielto/core/db/freeze_guard.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/domain/period/freeze.dart';
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
    required ScheduleType scheduleType,
    Decimal? amount,
    bool isAnchor = false,
    int? fixedDay,
    WeekdayOrdinal? weekdayOrdinal,
    Weekday? weekdayDay,
    int? dateRangeStart,
    int? dateRangeEnd,
    BoundaryAnchor? boundaryAnchor,
    int? boundaryCount,
    String? countryCode,
  }) {
    final ({String author, DateTime editedAt}) s = stamp();
    return db
        .into(db.incomeRecurrenceRules)
        .insertReturning(
          IncomeRecurrenceRulesCompanion.insert(
            id: SyncedRepository.newId(),
            spaceId: spaceId,
            title: title.trim(),
            scheduleType: scheduleType,
            amount: Value<Decimal?>(amount),
            isAnchor: Value<bool>(isAnchor),
            fixedDay: Value<int?>(fixedDay),
            weekdayOrdinal: Value<WeekdayOrdinal?>(weekdayOrdinal),
            weekdayDay: Value<Weekday?>(weekdayDay),
            dateRangeStart: Value<int?>(dateRangeStart),
            dateRangeEnd: Value<int?>(dateRangeEnd),
            boundaryAnchor: Value<BoundaryAnchor?>(boundaryAnchor),
            boundaryCount: Value<int?>(boundaryCount),
            countryCode: Value<String?>(countryCode),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: s.editedAt,
            createdAt: s.editedAt,
          ),
        );
  }

  /// Writes every schedule field, clearing the unused ones. Existing occurrences
  /// are left to the caller.
  Future<int> updateRule(
    String ruleId, {
    required String title,
    required ScheduleType scheduleType,
    Decimal? amount,
    int? fixedDay,
    WeekdayOrdinal? weekdayOrdinal,
    Weekday? weekdayDay,
    int? dateRangeStart,
    int? dateRangeEnd,
    BoundaryAnchor? boundaryAnchor,
    int? boundaryCount,
  }) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.incomeRecurrenceRules,
    )..where(($IncomeRecurrenceRulesTable t) => t.id.equals(ruleId))).write(
      IncomeRecurrenceRulesCompanion(
        title: Value<String>(title.trim()),
        scheduleType: Value<ScheduleType>(scheduleType),
        amount: Value<Decimal?>(amount),
        fixedDay: Value<int?>(fixedDay),
        weekdayOrdinal: Value<WeekdayOrdinal?>(weekdayOrdinal),
        weekdayDay: Value<Weekday?>(weekdayDay),
        dateRangeStart: Value<int?>(dateRangeStart),
        dateRangeEnd: Value<int?>(dateRangeEnd),
        boundaryAnchor: Value<BoundaryAnchor?>(boundaryAnchor),
        boundaryCount: Value<int?>(boundaryCount),
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
    required ScheduleType scheduleType,
    Decimal? amount,
    int? fixedDay,
    WeekdayOrdinal? weekdayOrdinal,
    Weekday? weekdayDay,
    int? dateRangeStart,
    int? dateRangeEnd,
    BoundaryAnchor? boundaryAnchor,
    int? boundaryCount,
    String? countryCode,
  }) async {
    final bool anchor =
        mode == BudgetMode.incomeDriven &&
        (await anchorsInSpace(spaceId)).isEmpty;
    return create(
      spaceId: spaceId,
      title: title,
      scheduleType: scheduleType,
      amount: amount,
      isAnchor: anchor,
      fixedDay: fixedDay,
      weekdayOrdinal: weekdayOrdinal,
      weekdayDay: weekdayDay,
      dateRangeStart: dateRangeStart,
      dateRangeEnd: dateRangeEnd,
      boundaryAnchor: boundaryAnchor,
      boundaryCount: boundaryCount,
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
  Future<int> deleteRule(String ruleId, {required BudgetMode mode}) async {
    await _refuseIfLastAnchor(ruleId, mode);
    return softDelete(ruleId);
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
  late final DeadlineGuard _deadline = DeadlineGuard(db: db);

  Future<Income?> byId(String id) =>
      (selectAlive()..where(($IncomesTable t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<FreezeState> freezeStateOf(String id) async {
    final Income? row = await byId(id);
    return _freeze.stateOf(row?.budgetPeriodId);
  }

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
  }) async {
    await _deadline.refuseIfBeyondDeadline(spaceId, expectedDate);

    final ({String author, DateTime editedAt}) s = stamp();
    return db
        .into(db.incomes)
        .insertReturning(
          IncomesCompanion.insert(
            id: SyncedRepository.newId(),
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
            clientEditedAt: s.editedAt,
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

  /// Expected dates of every occurrence of a rule, deleted ones included: a
  /// deleted date is not refilled.
  Future<Set<String>> materialisedDatesFor(String ruleId) async => <String>{
    for (final Income i in await occurrencesOf(ruleId)) i.expectedDate.toIso(),
  };

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

  /// Skips received rows.
  Future<int> updateFutureAmounts(String ruleId, Decimal? amount) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(db.incomes)..where(
          ($IncomesTable t) =>
              t.recurrenceRuleId.equals(ruleId) &
              t.isPaid.equals(false) &
              t.isDeleted.equals(false),
        ))
        .write(
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
