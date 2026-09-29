import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

enum RangeUnit { month, quarter, year }

/// A calendar range, never a budget period.
@immutable
class AnalyticsRange {
  const AnalyticsRange({required this.unit, required this.anchor});

  final RangeUnit unit;

  /// Any date inside the range; bounds are derived.
  final CalendarDate anchor;

  CalendarDate get from => switch (unit) {
    RangeUnit.month => anchor.firstOfMonth,
    RangeUnit.quarter => CalendarDate(anchor.year, _quarterFirstMonth, 1),
    RangeUnit.year => CalendarDate(anchor.year, 1, 1),
  };

  CalendarDate get to => switch (unit) {
    RangeUnit.month => anchor.lastOfMonth,
    RangeUnit.quarter => CalendarDate(
      anchor.year,
      _quarterFirstMonth,
      1,
    ).addMonths(2).lastOfMonth,
    RangeUnit.year => CalendarDate(anchor.year, 12, 31),
  };

  int get _quarterFirstMonth => (anchor.month - 1) ~/ 3 * 3 + 1;

  bool get exceedsAYear => from.addMonths(12).isBefore(to);

  AnalyticsRange step(int by) => AnalyticsRange(
    unit: unit,
    anchor: switch (unit) {
      RangeUnit.month => anchor.firstOfMonth.addMonths(by),
      RangeUnit.quarter => from.addMonths(by * 3),
      RangeUnit.year => CalendarDate(anchor.year + by, 1, 1),
    },
  );

  AnalyticsRange withUnit(RangeUnit next) =>
      AnalyticsRange(unit: next, anchor: anchor);

  @override
  bool operator ==(Object other) =>
      other is AnalyticsRange && other.unit == unit && other.anchor == anchor;

  @override
  int get hashCode => Object.hash(unit, anchor);
}

/// Opens on the current month.
class AnalyticsRangeController extends Notifier<AnalyticsRange> {
  @override
  AnalyticsRange build() => AnalyticsRange(
    unit: RangeUnit.month,
    anchor: ref.watch(spaceClockProvider).today(),
  );

  void step(int by) => state = state.step(by);

  void setUnit(RangeUnit unit) => state = state.withUnit(unit);
}

final NotifierProvider<AnalyticsRangeController, AnalyticsRange>
analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeController, AnalyticsRange>(
      AnalyticsRangeController.new,
    );

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
