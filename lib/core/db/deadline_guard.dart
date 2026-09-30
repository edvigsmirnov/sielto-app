import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/budget_period_repository.dart';
import 'package:sielto/domain/value/calendar_date.dart';

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
  const DeadlineGuard({required this.periods});

  final BudgetPeriodRepository periods;

  Future<void> refuseIfBeyondDeadline(String spaceId, CalendarDate date) async {
    final BudgetPeriod? period = await periods.continuousFor(spaceId);
    if (period == null || !period.deadlineIsHard) return;

    final CalendarDate? deadline = period.deadlineDate;
    if (deadline == null || !date.isAfter(deadline)) return;
    throw BeyondHardDeadline(deadline);
  }
}
