import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/deadline_guard.dart';
import 'package:sielto/core/db/freeze_guard.dart';
import 'package:sielto/core/db/repositories/budget_period_repository.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

class PaymentRepository extends SyncedRepository<$PaymentsTable, Payment> {
  PaymentRepository({
    required super.db,
    required super.clock,
    required super.userId,
  });

  /// Gap between manual positions, so a drag usually needs one write.
  static const int sortOrderGap = 1024;

  @override
  TableInfo<$PaymentsTable, Payment> get table => db.payments;

  late final FreezeGuard _freeze = FreezeGuard(db: db, clock: clock);
  late final DeadlineGuard _deadline = DeadlineGuard(
    periods: BudgetPeriodRepository(db: db, clock: clock, userId: userId),
  );

  /// Fields a frozen period protects. Category and notes stay editable.
  static bool _touchesProtected({
    required bool amount,
    required bool dueDate,
    required bool expenseType,
    required bool isPaid,
  }) => amount || dueDate || expenseType || isPaid;

  /// Ordered by date, manual position, then id. `sort_order` is not unique.
  Future<List<Payment>> inSpace(String spaceId) =>
      _selectInSpace(spaceId).get();

  Stream<List<Payment>> watchInSpace(String spaceId) =>
      _selectInSpace(spaceId).watch();

  /// Due between [from] and [to], inclusive.
  Stream<List<Payment>> watchAround(
    String spaceId,
    CalendarDate from,
    CalendarDate to,
  ) =>
      (_selectInSpace(spaceId)..where(
            ($PaymentsTable t) =>
                t.dueDate.isBiggerOrEqualValue(from.toIso()) &
                t.dueDate.isSmallerOrEqualValue(to.toIso()),
          ))
          .watch();

  SimpleSelectStatement<$PaymentsTable, Payment> _selectInSpace(
    String spaceId,
  ) =>
      selectAliveInSpace(spaceId)
        ..orderBy(<OrderClauseGenerator<$PaymentsTable>>[
          ($PaymentsTable t) => OrderingTerm(expression: t.dueDate),
          ($PaymentsTable t) => OrderingTerm(expression: t.sortOrder),
          ($PaymentsTable t) => OrderingTerm(expression: t.id),
        ]);

  Future<List<Payment>> onDay(String spaceId, CalendarDate day) =>
      _selectOnDay(spaceId, day).get();

  Stream<List<Payment>> watchOnDay(String spaceId, CalendarDate day) =>
      _selectOnDay(spaceId, day).watch();

  SimpleSelectStatement<$PaymentsTable, Payment> _selectOnDay(
    String spaceId,
    CalendarDate day,
  ) =>
      _selectInSpace(spaceId)
        ..where(($PaymentsTable t) => t.dueDate.equals(day.toIso()));

  Future<Payment?> byId(String id) =>
      (selectAlive()..where(($PaymentsTable t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Appends to the end of its day.
  Future<Payment> create({
    required String spaceId,
    required String title,
    required Decimal amount,
    required CalendarDate dueDate,
    required ExpenseType expenseType,
    String? categoryId,
    String? budgetPeriodId,
    String? groupRecurringId,
    String? notes,
    bool isPaid = false,
  }) async {
    await _deadline.refuseIfBeyondDeadline(spaceId, dueDate);

    final ({String author, DateTime editedAt}) s = stamp();
    final PaymentsCompanion row = PaymentsCompanion.insert(
      id: SyncedRepository.newId(),
      spaceId: spaceId,
      title: title.trim(),
      amount: amount,
      dueDate: dueDate,
      expenseType: expenseType,
      categoryId: Value<String?>(categoryId),
      budgetPeriodId: Value<String?>(budgetPeriodId),
      groupRecurringId: Value<String?>(groupRecurringId),
      notes: Value<String?>(notes),
      isPaid: Value<bool>(isPaid),
      sortOrder: Value<int>(await nextSortOrder(spaceId, dueDate)),
      syncStatus: const Value<SyncStatus>(SyncStatus.pending),
      lastModifiedBy: Value<String?>(s.author),
      clientEditedAt: s.editedAt,
      createdAt: s.editedAt,
    );
    return db.into(db.payments).insertReturning(row);
  }

  /// Applies only the given fields and re-stamps the row.
  Future<int> update(
    String id, {
    Value<String> title = const Value<String>.absent(),
    Value<Decimal> amount = const Value<Decimal>.absent(),
    Value<CalendarDate> dueDate = const Value<CalendarDate>.absent(),
    Value<ExpenseType> expenseType = const Value<ExpenseType>.absent(),
    Value<String?> categoryId = const Value<String?>.absent(),
    Value<String?> notes = const Value<String?>.absent(),
    Value<bool> isPaid = const Value<bool>.absent(),
    Value<int> sortOrder = const Value<int>.absent(),
  }) async {
    // Reordering is allowed in a frozen period.
    if (_touchesProtected(
      amount: amount.present,
      dueDate: dueDate.present,
      expenseType: expenseType.present,
      isPaid: isPaid.present,
    )) {
      final Payment? row = await byId(id);
      await _freeze.refuseIfFrozen(row?.budgetPeriodId);
      if (dueDate.present && row != null) {
        await _deadline.refuseIfBeyondDeadline(row.spaceId, dueDate.value);
      }
    }

    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.payments,
    )..where(($PaymentsTable t) => t.id.equals(id))).write(
      PaymentsCompanion(
        title: title.present
            ? Value<String>(title.value.trim())
            : const Value<String>.absent(),
        amount: amount,
        dueDate: dueDate,
        expenseType: expenseType,
        categoryId: categoryId,
        notes: notes,
        isPaid: isPaid,
        sortOrder: sortOrder,
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  /// Every live payment of [fromCategoryId], frozen periods included: the
  /// category stays editable there.
  Future<int> moveCategory(String fromCategoryId, String? toCategoryId) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(db.payments)..where(
          ($PaymentsTable t) =>
              t.categoryId.equals(fromCategoryId) & t.isDeleted.equals(false),
        ))
        .write(
          PaymentsCompanion(
            categoryId: Value<String?>(toCategoryId),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: Value<DateTime>(s.editedAt),
          ),
        );
  }

  Future<int> setPaid(String id, {required bool isPaid}) =>
      update(id, isPaid: Value<bool>(isPaid));

  /// Throws [PeriodFrozen] in a frozen period.
  @override
  Future<int> softDelete(String id) async {
    final Payment? row = await byId(id);
    await _freeze.refuseIfFrozen(row?.budgetPeriodId);
    return super.softDelete(id);
  }

  /// One row per occurrence, sharing a `group_recurring_id`.
  Future<String> createSeries({
    required String spaceId,
    required String title,
    required Decimal amount,
    required List<CalendarDate> dates,
    required ExpenseType expenseType,
    String? categoryId,
    String? notes,
  }) async {
    for (final CalendarDate date in dates) {
      await _deadline.refuseIfBeyondDeadline(spaceId, date);
    }
    final List<int> sortOrders = <int>[
      for (final CalendarDate date in dates) await nextSortOrder(spaceId, date),
    ];
    final String groupId = SyncedRepository.newId();
    final ({String author, DateTime editedAt}) s = stamp();

    await db.batch((Batch b) {
      b.insertAll(db.payments, <PaymentsCompanion>[
        for (final (int i, CalendarDate date) in dates.indexed)
          PaymentsCompanion.insert(
            id: SyncedRepository.newId(),
            spaceId: spaceId,
            title: title.trim(),
            amount: amount,
            dueDate: date,
            expenseType: expenseType,
            categoryId: Value<String?>(categoryId),
            groupRecurringId: Value<String>(groupId),
            notes: Value<String?>(notes),
            sortOrder: Value<int>(sortOrders[i]),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: s.editedAt,
            createdAt: s.editedAt,
          ),
      ]);
    });

    return groupId;
  }

  /// Skips paid rows.
  Future<int> updateSeriesFrom(
    String groupRecurringId,
    CalendarDate from, {
    Value<String> title = const Value<String>.absent(),
    Value<Decimal> amount = const Value<Decimal>.absent(),
    Value<ExpenseType> expenseType = const Value<ExpenseType>.absent(),
    Value<String?> categoryId = const Value<String?>.absent(),
    Value<String?> notes = const Value<String?>.absent(),
  }) => _writeSeries(
    groupRecurringId,
    from: from,
    title: title,
    amount: amount,
    expenseType: expenseType,
    categoryId: categoryId,
    notes: notes,
  );

  /// Every occurrence except paid ones.
  Future<int> updateWholeSeries(
    String groupRecurringId, {
    Value<String> title = const Value<String>.absent(),
    Value<Decimal> amount = const Value<Decimal>.absent(),
    Value<ExpenseType> expenseType = const Value<ExpenseType>.absent(),
    Value<String?> categoryId = const Value<String?>.absent(),
    Value<String?> notes = const Value<String?>.absent(),
  }) => _writeSeries(
    groupRecurringId,
    title: title,
    amount: amount,
    expenseType: expenseType,
    categoryId: categoryId,
    notes: notes,
  );

  /// Live occurrences in date order. A series has no rule row.
  Future<List<Payment>> seriesOf(String groupRecurringId) =>
      (selectAlive()
            ..where(
              ($PaymentsTable t) => t.groupRecurringId.equals(groupRecurringId),
            )
            ..orderBy(<OrderClauseGenerator<$PaymentsTable>>[
              ($PaymentsTable t) => OrderingTerm(expression: t.dueDate),
            ]))
          .get();

  /// Soft-deletes a whole series, or from [from] on. Frozen rows stay.
  Future<int> deleteSeries(
    String groupRecurringId, {
    CalendarDate? from,
  }) async {
    final List<String> ids = await _idsInSeries(
      groupRecurringId,
      from,
      unpaidOnly: false,
      skipFrozen: true,
    );
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.payments,
    )..where(($PaymentsTable t) => t.id.isIn(ids))).write(
      PaymentsCompanion(
        isDeleted: const Value<bool>(true),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  Future<int> _writeSeries(
    String groupRecurringId, {
    CalendarDate? from,
    Value<String> title = const Value<String>.absent(),
    Value<Decimal> amount = const Value<Decimal>.absent(),
    Value<ExpenseType> expenseType = const Value<ExpenseType>.absent(),
    Value<String?> categoryId = const Value<String?>.absent(),
    Value<String?> notes = const Value<String?>.absent(),
  }) async {
    // Title, category and notes stay editable in a frozen period.
    final List<String> ids = await _idsInSeries(
      groupRecurringId,
      from,
      unpaidOnly: true,
      skipFrozen: amount.present || expenseType.present,
    );
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.payments,
    )..where(($PaymentsTable t) => t.id.isIn(ids))).write(
      PaymentsCompanion(
        title: title.present
            ? Value<String>(title.value.trim())
            : const Value<String>.absent(),
        amount: amount,
        expenseType: expenseType,
        categoryId: categoryId,
        notes: notes,
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  Future<List<String>> _idsInSeries(
    String groupRecurringId,
    CalendarDate? from, {
    required bool unpaidOnly,
    required bool skipFrozen,
  }) async {
    final List<Payment> rows =
        await (db.select(db.payments)..where(($PaymentsTable t) {
              final Expression<bool> series = _seriesFilter(
                t,
                groupRecurringId,
                from,
              );
              return unpaidOnly ? series & t.isPaid.equals(false) : series;
            }))
            .get();
    return <String>[
      for (final Payment row in rows)
        if (!skipFrozen ||
            await _freeze.stateOf(row.budgetPeriodId) != FreezeState.frozen)
          row.id,
    ];
  }

  Expression<bool> _seriesFilter(
    $PaymentsTable t,
    String groupRecurringId,
    CalendarDate? from,
  ) {
    final Expression<bool> base =
        t.groupRecurringId.equals(groupRecurringId) & t.isDeleted.equals(false);
    return from == null
        ? base
        : base & t.dueDate.isBiggerOrEqualValue(from.toIso());
  }

  /// `auto` rows are rebound by date on recompute; `manual` rows keep their
  /// period.
  Future<int> setPeriod(
    String id,
    String? periodId, {
    PeriodAssignment? assignment,
  }) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.payments,
    )..where(($PaymentsTable t) => t.id.equals(id))).write(
      PaymentsCompanion(
        budgetPeriodId: Value<String?>(periodId),
        periodAssignment: assignment == null
            ? const Value<PeriodAssignment>.absent()
            : Value<PeriodAssignment>(assignment),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  Future<List<Payment>> autoAssignedIn(String spaceId) =>
      (selectAliveInSpace(spaceId)..where(
            ($PaymentsTable t) =>
                t.periodAssignment.equalsValue(PeriodAssignment.auto),
          ))
          .get();

  /// Rows pinned to a period by hand.
  Future<List<Payment>> manuallyAssignedIn(String spaceId) =>
      (selectAliveInSpace(spaceId)..where(
            ($PaymentsTable t) =>
                t.periodAssignment.equalsValue(PeriodAssignment.manual),
          ))
          .get();

  Future<int> nextSortOrder(String spaceId, CalendarDate day) async {
    final List<Payment> rows = await onDay(spaceId, day);
    if (rows.isEmpty) return 0;
    return rows.last.sortOrder + sortOrderGap;
  }

  /// Titles used before in this Space that start with [prefix], one per
  /// `lower(trim(title))` key, most frequent spelling.
  Future<List<String>> titleSuggestions(
    String spaceId,
    String prefix, {
    int limit = 8,
  }) async {
    final String trimmed = prefix.trim();
    if (trimmed.isEmpty) return const <String>[];

    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT title, count(*) AS uses FROM payments '
          'WHERE space_id = ?1 AND is_deleted = 0 '
          "  AND lower(trim(title)) LIKE ?2 || '%' "
          'GROUP BY lower(trim(title)), title '
          'ORDER BY uses DESC, title ASC LIMIT ?3',
          variables: <Variable<Object>>[
            Variable<String>(spaceId),
            Variable<String>(trimmed.toLowerCase()),
            // Several spellings collapse into one below.
            Variable<int>(limit * 4),
          ],
          readsFrom: <ResultSetImplementation<HasResultSet, Object>>{
            db.payments,
          },
        )
        .get();

    final Map<String, String> best = <String, String>{};
    for (final QueryRow row in rows) {
      final String title = row.read<String>('title');
      best.putIfAbsent(title.trim().toLowerCase(), () => title);
      if (best.length == limit) break;
    }
    return best.values.toList();
  }

  /// Soft-deleted payments do not count.
  Future<bool> anyVisibleInCategory(String categoryId) async {
    final Payment? hit =
        await (selectAlive()
              ..where(($PaymentsTable t) => t.categoryId.equals(categoryId))
              ..limit(1))
            .getSingleOrNull();
    return hit != null;
  }
}
