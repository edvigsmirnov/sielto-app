import 'package:drift/drift.dart';
import 'package:sielto/core/db/converters.dart';
import 'package:sielto/domain/value/enums.dart';

/// Syncable tables carry [SyncColumns] and UUIDv4 keys. Changes are additive:
/// add nullable columns, never rename or drop.

mixin SyncColumns on Table {
  BoolColumn get isDeleted =>
      boolean().named('is_deleted').withDefault(const Constant<bool>(false))();

  TextColumn get syncStatus => textEnum<SyncStatus>()
      .named('sync_status')
      .withDefault(const Constant<String>('none'))();

  TextColumn get lastModifiedBy =>
      text().named('last_modified_by').nullable()();

  /// Device time of the edit; last-write-wins compares it.
  DateTimeColumn get clientEditedAt => dateTime().named('client_edited_at')();

  /// Set by the server on receipt. Null until uploaded.
  DateTimeColumn get serverReceivedAt =>
      dateTime().named('server_received_at').nullable()();
}

/// A Space. `budgetMode` is never updated.
class Spaces extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get spaceType => textEnum<SpaceType>().named('space_type')();
  TextColumn get budgetMode => textEnum<BudgetMode>().named('budget_mode')();
  TextColumn get ownerId => text().named('owner_id')();

  TextColumn get storageMode => textEnum<StorageMode>().named('storage_mode')();

  /// Overrides the default country for holidays.
  TextColumn get countryCode => text().named('country_code').nullable()();

  /// Defines "today" for every member.
  TextColumn get timezone => text()();

  /// Frozen after the first record.
  TextColumn get currencyCode => text().named('currency_code')();

  /// 0 disables invites; null means no limit.
  IntColumn get maxMembers => integer()
      .named('max_members')
      .nullable()
      .withDefault(const Constant<int>(0))();

  /// Read-only local archive. Never uploaded.
  BoolColumn get isArchived =>
      boolean().named('is_archived').withDefault(const Constant<bool>(false))();

  /// Flow's current balance.
  TextColumn get manualBalance =>
      text().named('manual_balance').nullable().map(const DecimalConverter())();

  DateTimeColumn get manualBalanceUpdatedAt =>
      dateTime().named('manual_balance_updated_at').nullable()();

  /// Raised only with creator consent.
  IntColumn get minSchemaVersion => integer()
      .named('min_schema_version')
      .withDefault(const Constant<int>(1))();

  TextColumn get feedOrderMode => textEnum<FeedOrderMode>()
      .named('feed_order_mode')
      .withDefault(const Constant<String>('grouped'))();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<String> get customConstraints => <String>[
    'CHECK (length(trim(title)) > 0)',
    'CHECK (manual_balance IS NULL OR CAST(manual_balance AS REAL) >= 0)',
    'CHECK (max_members IS NULL OR max_members >= 0)',
  ];
}

/// Membership only. Nicknames: [UserProfiles]; private notes: [MemberLocalLabels].
class SpaceMembers extends Table {
  TextColumn get spaceId => text().named('space_id').references(Spaces, #id)();
  TextColumn get userId => text().named('user_id')();
  DateTimeColumn get joinedAt => dateTime().named('joined_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{spaceId, userId};
}

/// A viewer's private notes about another member. Synced to the viewer's
/// devices only.
class MemberLocalLabels extends Table with SyncColumns {
  TextColumn get spaceId => text().named('space_id').references(Spaces, #id)();
  TextColumn get viewerUserId => text().named('viewer_user_id')();
  TextColumn get targetUserId => text().named('target_user_id')();
  TextColumn get localName => text().named('local_name').nullable()();
  TextColumn get localRole => text().named('local_role').nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    spaceId,
    viewerUserId,
    targetUserId,
  };
}

/// Public nickname, visible to members of shared Spaces.
class UserProfiles extends Table with SyncColumns {
  TextColumn get userId => text().named('user_id')();
  TextColumn get nickname => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId};

  @override
  List<String> get customConstraints => <String>[
    'CHECK (length(trim(nickname)) > 0)',
  ];
}

/// The title freezes once a visible payment uses the category; colour, icon
/// and default type stay editable.
class Categories extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get spaceId => text().named('space_id').references(Spaces, #id)();
  TextColumn get title => text()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();

  /// Starter category key; the title is then shown translated. Cleared on
  /// rename.
  TextColumn get starterKey => text().named('starter_key').nullable()();

  /// Default for new payments only.
  TextColumn get expenseType => textEnum<ExpenseType>()
      .named('expense_type')
      .withDefault(const Constant<String>('variable'))();

  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant<int>(0))();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<String> get customConstraints => <String>[
    'CHECK (length(trim(title)) > 0)',
  ];
}

/// Period boundaries for all modes. Flow and Budget hold one `continuous` row
/// with a null end_date.
class BudgetPeriods extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get spaceId => text().named('space_id').references(Spaces, #id)();
  TextColumn get periodType => textEnum<PeriodType>().named('period_type')();

  TextColumn get startDate =>
      text().named('start_date').map(const CalendarDateConverter())();

  /// Null for `continuous`.
  TextColumn get endDate =>
      text().named('end_date').nullable().map(const CalendarDateConverter())();

  /// Anchor income uncertainty window. Null for `continuous`.
  TextColumn get windowStart => text()
      .named('window_start')
      .nullable()
      .map(const CalendarDateConverter())();

  TextColumn get windowEnd => text()
      .named('window_end')
      .nullable()
      .map(const CalendarDateConverter())();

  TextColumn get anchorDate => text()
      .named('anchor_date')
      .nullable()
      .map(const CalendarDateConverter())();

  /// Computed without holiday data; may still narrow.
  BoolColumn get holidayDataIncomplete => boolean()
      .named('holiday_data_incomplete')
      .withDefault(const Constant<bool>(false))();

  /// Budget mode only.
  TextColumn get deadlineDate => text()
      .named('deadline_date')
      .nullable()
      .map(const CalendarDateConverter())();

  BoolColumn get deadlineIsHard => boolean()
      .named('deadline_is_hard')
      .withDefault(const Constant<bool>(false))();

  TextColumn get budgetTarget =>
      text().named('budget_target').nullable().map(const DecimalConverter())();

  /// Temporary unfreeze of a closed period.
  DateTimeColumn get unfrozenUntil =>
      dateTime().named('unfrozen_until').nullable()();

  TextColumn get unfreezeReason => text().named('unfreeze_reason').nullable()();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<String> get customConstraints => <String>[
    // Minimum length is one day.
    'CHECK (end_date IS NULL OR end_date >= start_date)',
    'CHECK (window_end IS NULL OR window_start IS NULL OR window_end >= window_start)',
    'CHECK (budget_target IS NULL OR CAST(budget_target AS REAL) >= 0)',
  ];
}

/// Repetition rule for regular incomes.
class IncomeRecurrenceRules extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get spaceId => text().named('space_id').references(Spaces, #id)();
  TextColumn get title => text()();

  /// Null when the amount is not known in advance.
  TextColumn get amount => text().nullable().map(const DecimalConverter())();

  /// income_driven Spaces only.
  BoolColumn get isAnchor =>
      boolean().named('is_anchor').withDefault(const Constant<bool>(false))();

  TextColumn get scheduleType =>
      textEnum<ScheduleType>().named('schedule_type')();

  /// fixed_date
  IntColumn get fixedDay => integer().named('fixed_day').nullable()();

  /// weekday_rule
  TextColumn get weekdayOrdinal =>
      textEnum<WeekdayOrdinal>().named('weekday_ordinal').nullable()();
  TextColumn get weekdayDay =>
      textEnum<Weekday>().named('weekday_day').nullable()();

  /// date_range
  IntColumn get dateRangeStart =>
      integer().named('date_range_start').nullable()();
  IntColumn get dateRangeEnd => integer().named('date_range_end').nullable()();

  /// boundary_days
  TextColumn get boundaryAnchor =>
      textEnum<BoundaryAnchor>().named('boundary_anchor').nullable()();
  IntColumn get boundaryCount => integer().named('boundary_count').nullable()();

  /// Overrides the Space country for holidays.
  TextColumn get countryCode => text().named('country_code').nullable()();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<String> get customConstraints => <String>[
    'CHECK (length(trim(title)) > 0)',
    'CHECK (amount IS NULL OR CAST(amount AS REAL) > 0)',
    'CHECK (fixed_day IS NULL OR (fixed_day BETWEEN 1 AND 31))',
    'CHECK (date_range_start IS NULL OR (date_range_start BETWEEN 1 AND 31))',
    'CHECK (date_range_end IS NULL OR (date_range_end BETWEEN 1 AND 31))',
    'CHECK (boundary_count IS NULL OR boundary_count > 0)',
    // Each schedule type sets only its own fields.
    "CHECK (schedule_type <> 'fixedDate' OR fixed_day IS NOT NULL)",
    "CHECK (schedule_type <> 'weekdayRule' OR (weekday_ordinal IS NOT NULL AND weekday_day IS NOT NULL))",
    "CHECK (schedule_type <> 'dateRange' OR (date_range_start IS NOT NULL AND date_range_end IS NOT NULL))",
    "CHECK (schedule_type <> 'boundaryDays' OR (boundary_anchor IS NOT NULL AND boundary_count IS NOT NULL))",
  ];
}

/// An expected or received income. Regular incomes have one row per
/// occurrence.
class Incomes extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get spaceId => text().named('space_id').references(Spaces, #id)();

  /// Null for a one-off income.
  TextColumn get recurrenceRuleId => text()
      .named('recurrence_rule_id')
      .nullable()
      .references(IncomeRecurrenceRules, #id)();

  TextColumn get title => text()();
  TextColumn get amount => text().nullable().map(const DecimalConverter())();

  TextColumn get expectedDate =>
      text().named('expected_date').map(const CalendarDateConverter())();

  /// Actual receipt date. Changes neither the period nor the schedule.
  TextColumn get actualDate => text()
      .named('actual_date')
      .nullable()
      .map(const CalendarDateConverter())();

  TextColumn get budgetPeriodId => text()
      .named('budget_period_id')
      .nullable()
      .references(BudgetPeriods, #id)();

  /// Manual order within a day. Sparse (gap 1024), not unique; ties break on
  /// id.
  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant<int>(0))();

  /// Received.
  BoolColumn get isPaid =>
      boolean().named('is_paid').withDefault(const Constant<bool>(false))();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<String> get customConstraints => <String>[
    'CHECK (length(trim(title)) > 0)',
    'CHECK (amount IS NULL OR CAST(amount AS REAL) > 0)',
  ];
}

/// An expense. Always dated.
class Payments extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get spaceId => text().named('space_id').references(Spaces, #id)();

  TextColumn get budgetPeriodId => text()
      .named('budget_period_id')
      .nullable()
      .references(BudgetPeriods, #id)();

  /// `manual` keeps the period on recalculation.
  TextColumn get periodAssignment => textEnum<PeriodAssignment>()
      .named('period_assignment')
      .withDefault(const Constant<String>('auto'))();

  TextColumn get categoryId =>
      text().named('category_id').nullable().references(Categories, #id)();

  TextColumn get groupRecurringId =>
      text().named('group_recurring_id').nullable()();

  TextColumn get title => text()();
  TextColumn get amount => text().map(const DecimalConverter())();

  TextColumn get dueDate =>
      text().named('due_date').map(const CalendarDateConverter())();

  TextColumn get expenseType => textEnum<ExpenseType>().named('expense_type')();

  /// See [Incomes.sortOrder].
  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant<int>(0))();

  BoolColumn get isPaid =>
      boolean().named('is_paid').withDefault(const Constant<bool>(false))();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<String> get customConstraints => <String>[
    'CHECK (length(trim(title)) > 0)',
    // Zero is a dated to-do; the sign comes from the record type.
    'CHECK (CAST(amount AS REAL) >= 0)',
  ];
}

/// Public holidays per country and year. Device-local cache; not synced.
class HolidayCache extends Table {
  TextColumn get id => text()();
  TextColumn get countryCode => text().named('country_code')();
  IntColumn get year => integer()();

  /// JSON array of `YYYY-MM-DD`.
  TextColumn get holidayDates => text().named('holiday_dates')();

  DateTimeColumn get fetchedAt => dateTime().named('fetched_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{countryCode, year},
  ];
}

/// User-added non-working days. Per device; applies to every Space with the
/// same country.
class CustomNonWorkingDays extends Table {
  TextColumn get id => text()();
  TextColumn get date => text().map(const CalendarDateConverter())();
  TextColumn get title => text().nullable()();

  /// Null applies the day to every country.
  TextColumn get countryCode => text().named('country_code').nullable()();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{date, countryCode},
  ];
}
