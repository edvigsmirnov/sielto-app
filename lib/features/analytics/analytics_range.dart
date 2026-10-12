import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/space/period_ledger.dart';

enum RangeUnit { period, month, quarter, year, custom }

/// A calendar range. A period range copies a budget period's dates.
@immutable
class AnalyticsRange {
  const AnalyticsRange({required this.unit, required this.anchor, this.end});

  /// Explicit bounds for a period or custom range.
  const AnalyticsRange.between(this.unit, CalendarDate from, CalendarDate to)
    : anchor = from,
      end = to;

  final RangeUnit unit;

  /// Any date inside a month, quarter or year; the first day otherwise.
  final CalendarDate anchor;

  /// Last day of a period or custom range.
  final CalendarDate? end;

  CalendarDate get from => switch (unit) {
    RangeUnit.month => anchor.firstOfMonth,
    RangeUnit.quarter => CalendarDate(anchor.year, _quarterFirstMonth, 1),
    RangeUnit.year => CalendarDate(anchor.year, 1, 1),
    RangeUnit.period || RangeUnit.custom => anchor,
  };

  CalendarDate get to => switch (unit) {
    RangeUnit.month => anchor.lastOfMonth,
    RangeUnit.quarter => CalendarDate(
      anchor.year,
      _quarterFirstMonth,
      1,
    ).addMonths(2).lastOfMonth,
    RangeUnit.year => CalendarDate(anchor.year, 12, 31),
    RangeUnit.period || RangeUnit.custom => end ?? anchor,
  };

  int get _quarterFirstMonth => (anchor.month - 1) ~/ 3 * 3 + 1;

  bool get exceedsAYear => from.addMonths(12).isBefore(to);

  /// A custom range moves by its own length. Periods step through the list
  /// of periods instead.
  AnalyticsRange step(int by) => switch (unit) {
    RangeUnit.month => AnalyticsRange(
      unit: unit,
      anchor: anchor.firstOfMonth.addMonths(by),
    ),
    RangeUnit.quarter => AnalyticsRange(
      unit: unit,
      anchor: from.addMonths(by * 3),
    ),
    RangeUnit.year => AnalyticsRange(
      unit: unit,
      anchor: CalendarDate(anchor.year + by, 1, 1),
    ),
    RangeUnit.custom || RangeUnit.period => AnalyticsRange.between(
      unit,
      from.addDays(by * (from.daysUntil(to) + 1)),
      to.addDays(by * (from.daysUntil(to) + 1)),
    ),
  };

  AnalyticsRange withUnit(RangeUnit next) =>
      AnalyticsRange(unit: next, anchor: from);

  @override
  bool operator ==(Object other) =>
      other is AnalyticsRange &&
      other.unit == unit &&
      other.anchor == anchor &&
      other.end == end;

  @override
  int get hashCode => Object.hash(unit, anchor, end);
}

/// The range picked in Analytics. Null is the default, and closing
/// Analytics or opening another Space goes back to it.
class AnalyticsChoiceController extends Notifier<AnalyticsRange?> {
  @override
  AnalyticsRange? build() {
    ref.watch(currentSpaceIdProvider);
    return null;
  }

  void choose(AnalyticsRange range) => state = range;
}

final NotifierProvider<AnalyticsChoiceController, AnalyticsRange?>
analyticsChoiceProvider =
    NotifierProvider<AnalyticsChoiceController, AnalyticsRange?>(
      AnalyticsChoiceController.new,
    );

/// The picked range, else the period containing today, else this month.
final Provider<AnalyticsRange> analyticsRangeProvider =
    Provider<AnalyticsRange>((Ref ref) {
      final AnalyticsRange? chosen = ref.watch(analyticsChoiceProvider);
      if (chosen != null) return chosen;
      final CalendarDate today = ref.watch(spaceClockProvider).today();
      final BudgetPeriod? current = periodOn(
        ref.watch(incomePeriodsProvider),
        today,
      );
      return current == null
          ? AnalyticsRange(unit: RangeUnit.month, anchor: today)
          : periodRange(current, today);
    });

BudgetPeriod? periodOn(List<BudgetPeriod> periods, CalendarDate day) {
  for (final BudgetPeriod p in periods) {
    final CalendarDate? end = p.endDate;
    if (!p.startDate.isAfter(day) && (end == null || !end.isBefore(day))) {
      return p;
    }
  }
  return null;
}

/// An open-ended period runs to [today].
AnalyticsRange periodRange(BudgetPeriod p, CalendarDate today) =>
    AnalyticsRange.between(RangeUnit.period, p.startDate, p.endDate ?? today);

/// Steps the shown range; a period range moves to the neighbouring period.
void stepAnalyticsRange(WidgetRef ref, int by) {
  final AnalyticsRange range = ref.read(analyticsRangeProvider);
  if (range.unit != RangeUnit.period) {
    ref.read(analyticsChoiceProvider.notifier).choose(range.step(by));
    return;
  }
  final List<BudgetPeriod> periods = ref.read(incomePeriodsProvider);
  final int at = periods.indexWhere(
    (BudgetPeriod p) => p.startDate == range.from,
  );
  final int next = at + by;
  if (at < 0 || next < 0 || next >= periods.length) return;
  ref
      .read(analyticsChoiceProvider.notifier)
      .choose(periodRange(periods[next], ref.read(spaceClockProvider).today()));
}

/// Switches the unit around the shown range's first day.
void setAnalyticsUnit(WidgetRef ref, RangeUnit unit) {
  final AnalyticsRange range = ref.read(analyticsRangeProvider);
  final CalendarDate today = ref.read(spaceClockProvider).today();
  final AnalyticsRange next = switch (unit) {
    RangeUnit.period => switch (periodOn(
      ref.read(incomePeriodsProvider),
      range.from,
    )) {
      final BudgetPeriod p => periodRange(p, today),
      null => range,
    },
    _ => range.withUnit(unit),
  };
  ref.read(analyticsChoiceProvider.notifier).choose(next);
}

/// Null shows everything.
class ExpenseTypeFilterController extends Notifier<ExpenseType?> {
  @override
  ExpenseType? build() => null;

  void select(ExpenseType? type) => state = type;
}

final NotifierProvider<ExpenseTypeFilterController, ExpenseType?>
expenseTypeFilterProvider =
    NotifierProvider<ExpenseTypeFilterController, ExpenseType?>(
      ExpenseTypeFilterController.new,
    );

enum AnalyticsGrouping { category, name }

class AnalyticsGroupingController extends Notifier<AnalyticsGrouping> {
  @override
  AnalyticsGrouping build() => AnalyticsGrouping.category;

  void select(AnalyticsGrouping grouping) => state = grouping;
}

final NotifierProvider<AnalyticsGroupingController, AnalyticsGrouping>
analyticsGroupingProvider =
    NotifierProvider<AnalyticsGroupingController, AnalyticsGrouping>(
      AnalyticsGroupingController.new,
    );
