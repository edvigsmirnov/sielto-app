import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/holidays/holiday_source.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/periods/holiday_service.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// 1.5x the median of spending days. Null below [minimumSample] spending days.
Decimal? highLoadThreshold(Iterable<Decimal> dailyExpenses) {
  final List<Decimal> spent = <Decimal>[
    for (final Decimal d in dailyExpenses)
      if (d > Decimal.zero) d,
  ]..sort();
  if (spent.length < minimumSample) return null;

  final Decimal median = spent.length.isOdd
      ? spent[spent.length ~/ 2]
      : ((spent[spent.length ~/ 2 - 1] + spent[spent.length ~/ 2]) /
                Decimal.fromInt(2))
            .toDecimal(scaleOnInfinitePrecision: 2);
  return (median * Decimal.parse('1.5')).round(scale: 2);
}

const int minimumSample = 6;

const int loadSampleMonths = 3;

/// Cell decorations beyond the figures.
@immutable
class DayMark {
  const DayMark({
    this.isNonWorking = false,
    this.isHoliday = false,
    this.isUncertainIncome = false,
    this.deadline,
    this.isHighLoad = false,
  });

  static const DayMark none = DayMark();

  /// Weekend, public holiday or user-marked day.
  final bool isNonWorking;

  /// Public holiday or user-marked day, not a plain weekend.
  final bool isHoliday;

  /// Inside an anchor income's `[windowStart, windowEnd]`.
  final bool isUncertainIncome;

  final DeadlineKind? deadline;

  /// See [highLoadThreshold].
  final bool isHighLoad;

  bool get isPlain =>
      !isNonWorking && !isUncertainIncome && !isHighLoad && deadline == null;

  DayMark copyWith({
    bool? isUncertainIncome,
    DeadlineKind? deadline,
    bool? isHighLoad,
  }) => DayMark(
    isNonWorking: isNonWorking,
    isHoliday: isHoliday,
    isUncertainIncome: isUncertainIncome ?? this.isUncertainIncome,
    deadline: deadline ?? this.deadline,
    isHighLoad: isHighLoad ?? this.isHighLoad,
  );
}

enum DeadlineKind { soft, hard }

/// Only days with a decoration are present.
@immutable
class DayMarks {
  const DayMarks(this._marks, {required this.threshold});

  static const DayMarks empty = DayMarks(
    <CalendarDate, DayMark>{},
    threshold: null,
  );

  final Map<CalendarDate, DayMark> _marks;

  /// Null without enough history.
  final Decimal? threshold;

  DayMark operator [](CalendarDate date) => _marks[date] ?? DayMark.none;
}

/// Decorations for [view] around the selected date. Type inferred:
/// `flutter_riverpod` does not export `FutureProviderFamily`.
final dayMarksProvider = FutureProvider.family<DayMarks, CalendarView>((
  Ref ref,
  CalendarView view,
) async {
  final Space? space = ref.watch(currentSpaceProvider);
  // The Year view draws none.
  if (space == null || view == CalendarView.year) return DayMarks.empty;

  final CalendarDate around = ref.watch(selectedDateProvider);
  final ({CalendarDate from, CalendarDate to}) range = rangeOf(view, around);

  // The browsed year, which can be outside the materialisation years.
  final ResolvedCalendar resolved = await ref.watch(
    calendarForYearProvider(around.year).future,
  );
  final WorkingDayCalendar calendar = resolved.calendar;

  final Map<CalendarDate, DayMark> marks = <CalendarDate, DayMark>{};
  DayMark at(CalendarDate date) => marks[date] ?? DayMark.none;

  for (CalendarDate d = range.from; !d.isAfter(range.to); d = d.addDays(1)) {
    if (!calendar.isNonWorkingDay(d)) continue;
    marks[d] = DayMark(isNonWorking: true, isHoliday: calendar.isDayOff(d));
  }

  final List<BudgetPeriod> periods =
      ref.watch(spacePeriodsProvider).value ?? const <BudgetPeriod>[];
  for (final BudgetPeriod p in periods) {
    final CalendarDate? start = p.windowStart;
    final CalendarDate? end = p.windowEnd;
    // A one-day window is certain.
    if (start != null && end != null && start != end) {
      for (CalendarDate d = start; !d.isAfter(end); d = d.addDays(1)) {
        if (d.isBefore(range.from) || d.isAfter(range.to)) continue;
        marks[d] = at(d).copyWith(isUncertainIncome: true);
      }
    }

    final CalendarDate? deadline = p.deadlineDate;
    if (deadline != null) {
      marks[deadline] = at(deadline).copyWith(
        deadline: p.deadlineIsHard ? DeadlineKind.hard : DeadlineKind.soft,
      );
    }
  }

  // The threshold comes from recent history, not from the range on screen.
  ref.watch(spacePaymentsProvider);
  final CalendarDate today = ref.watch(spaceClockProvider).today();
  final Map<CalendarDate, DayTotals> history = await ref
      .watch(repositoriesProvider)
      .calendar
      .dailyTotals(space.id, today.addMonths(-loadSampleMonths), today);
  final Decimal? threshold = highLoadThreshold(
    history.values.map((DayTotals t) => t.expenses),
  );

  if (threshold != null) {
    final Map<CalendarDate, DayTotals> totals = await ref
        .watch(repositoriesProvider)
        .calendar
        .dailyTotals(space.id, range.from, range.to);
    for (final MapEntry<CalendarDate, DayTotals> e in totals.entries) {
      if (e.value.expenses < threshold) continue;
      marks[e.key] = at(e.key).copyWith(isHighLoad: true);
    }
  }

  return DayMarks(marks, threshold: threshold);
});

final FutureProvider<Map<CalendarDate, List<String>>> holidayNamesProvider =
    FutureProvider<Map<CalendarDate, List<String>>>((Ref ref) {
      final String? code =
          ref.watch(currentSpaceProvider)?.countryCode ??
          ref.watch(defaultCountryProvider);
      if (code == null) return const <CalendarDate, List<String>>{};
      return const HolidayBundle().namesFor(code);
    });

/// Null on a working day or plain weekend; else the custom day's title or the
/// holiday names, empty when unknown.
final dayOffNamesProvider = Provider.family<List<String>?, CalendarDate>((
  Ref ref,
  CalendarDate day,
) {
  final DayMark mark =
      (ref.watch(dayMarksProvider(CalendarView.day)).value ??
      DayMarks.empty)[day];
  if (!mark.isHoliday) return null;
  for (final CustomNonWorkingDay c
      in ref.watch(customNonWorkingDaysProvider).value ??
          const <CustomNonWorkingDay>[]) {
    final String? title = c.title?.trim();
    if (c.date == day && title != null && title.isNotEmpty) {
      return <String>[title];
    }
  }
  return ref.watch(holidayNamesProvider).value?[day] ?? const <String>[];
});
