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

  /// Null without a hard deadline.
  Future<CalendarDate?> hardDeadline(String spaceId) async {
    final BudgetPeriod? period = await periods.continuousFor(spaceId);
    return period != null && period.deadlineIsHard ? period.deadlineDate : null;
  }

  Future<void> refuseIfBeyondDeadline(String spaceId, CalendarDate date) async {
    final CalendarDate? deadline = await hardDeadline(spaceId);
    if (deadline == null || !date.isAfter(deadline)) return;
    throw BeyondHardDeadline(deadline);
  }
}
