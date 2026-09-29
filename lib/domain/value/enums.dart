/// Enumerated columns, stored by name. Add cases; never rename or remove.
library;

/// Set at creation, never updated.
enum BudgetMode { incomeDriven, budget, flow }

/// Where a Space lives; not the per-row [SyncStatus].
enum StorageMode { local, cloud }

/// Cosmetic.
enum SpaceType { personal, family, trip, project, custom }

/// Row order within a day in the Feed.
enum FeedOrderMode { grouped, free }

enum ExpenseType { mandatory, variable }

enum PeriodAssignment { auto, manual }

enum SyncStatus { none, pending, synced }

/// `continuous`: the single row of a Flow or Budget Space. `incomeDriven`: one
/// row per income cycle.
enum PeriodType { continuous, incomeDriven }

enum ScheduleType { fixedDate, weekdayRule, dateRange, boundaryDays }

/// No `fifth`: not every month has one.
enum WeekdayOrdinal { first, second, third, fourth, last }

enum Weekday { monday, tuesday, wednesday, thursday, friday, saturday, sunday }

enum BoundaryAnchor { start, end }
