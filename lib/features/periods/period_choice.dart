import 'package:meta/meta.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// Period a payment is filed under. [byDate] follows the due date; the others
/// are pinned and survive recomputes.
enum PeriodChoice { byDate, current, next }

@immutable
class PeriodPair {
  const PeriodPair({required this.current, required this.next});

  /// Null when no cycle covers the date.
  final BudgetPeriod? current;

  final BudgetPeriod? next;

  bool get isEmpty => current == null && next == null;

  BudgetPeriod? forChoice(PeriodChoice choice) => switch (choice) {
    PeriodChoice.byDate || PeriodChoice.current => current,
    PeriodChoice.next => next,
  };
}

/// [periods] must be oldest first.
PeriodPair periodsAround(List<BudgetPeriod> periods, CalendarDate date) {
  for (int i = 0; i < periods.length; i++) {
    final BudgetPeriod p = periods[i];
    if (p.periodType != PeriodType.incomeDriven) continue;
    if (p.startDate.isAfter(date)) continue;
    final CalendarDate? end = p.endDate;
    if (end != null && end.isBefore(date)) continue;
    return PeriodPair(
      current: p,
      next: i + 1 < periods.length ? periods[i + 1] : null,
    );
  }
  return const PeriodPair(current: null, next: null);
}

/// True when [date] is inside an anchor's uncertainty window, so either cycle
/// may apply.
bool periodIsAmbiguousOn(List<BudgetPeriod> periods, CalendarDate date) {
  for (final BudgetPeriod p in periods) {
    if (p.periodType != PeriodType.incomeDriven) continue;
    final CalendarDate? from = p.windowStart;
    final CalendarDate? to = p.windowEnd;
    if (from == null || to == null || from == to) continue;
    if (!from.isAfter(date) && !to.isBefore(date)) return true;
  }
  return false;
}

/// A pin to any other period reads as [PeriodChoice.byDate].
PeriodChoice choiceOf(Payment payment, PeriodPair pair) {
  if (payment.periodAssignment != PeriodAssignment.manual) {
    return PeriodChoice.byDate;
  }
  if (payment.budgetPeriodId == pair.next?.id) return PeriodChoice.next;
  if (payment.budgetPeriodId == pair.current?.id) return PeriodChoice.current;
  return PeriodChoice.byDate;
}
