import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// A record dated after a hard deadline.
class BeyondHardDeadline implements Exception {
  const BeyondHardDeadline(this.deadline);

  final CalendarDate deadline;

  @override
  String toString() => 'BeyondHardDeadline: $deadline';
}

/// Refuses records dated after a Budget Space's hard deadline. A soft
/// deadline refuses nothing.
class DeadlineGuard {
  const DeadlineGuard({required this.db});

  final AppDatabase db;

  Future<void> refuseIfBeyondDeadline(String spaceId, CalendarDate date) async {
    final BudgetPeriod? period =
        await (db.select(db.budgetPeriods)..where(
              ($BudgetPeriodsTable t) =>
                  t.spaceId.equals(spaceId) &
                  t.periodType.equalsValue(PeriodType.continuous) &
                  t.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (period == null || !period.deadlineIsHard) return;

    final CalendarDate? deadline = period.deadlineDate;
    if (deadline == null || !date.isAfter(deadline)) return;
    throw BeyondHardDeadline(deadline);
  }
}
