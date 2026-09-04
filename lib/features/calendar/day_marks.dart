import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/periods/holiday_service.dart';

/// The threshold above which a day is drawn as heavily loaded (spec 8.1).
///
/// Spec 8.1 offers two ways to set it: a figure in Space settings, or 1.5x the
/// median of recent daily spending. The median is what is implemented — it
/// needs no configuration, adapts to how much the Space actually moves, and a
/// number that has to be guessed at before the first month of data is a
/// setting nobody can fill in usefully.
///
/// The median of *spending days*, not of every day: a Space with records on
/// eight days a month has a median of zero across the calendar, and every
/// single day would clear 1.5x zero.
///
/// Null when there is too little to compare against. Below [minimumSample]
/// days the median is one or two figures, and marking half of them as heavy
/// says nothing.
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

/// Spending days needed before the threshold means anything.
const int minimumSample = 6;

/// Months of history the median is taken over (spec 8.1).
const int loadSampleMonths = 3;

/// What decorates one cell beyond its figures (spec 8.1).
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

  /// Weekend, public holiday or a day the user marked. Drawn as a wash.
  final bool isNonWorking;

  /// A public holiday or a custom non-working day, as opposed to a plain
  /// weekend. Earns the corner dot on top of the wash.
  final bool isHoliday;

  /// Inside an anchor income's `[windowStart, windowEnd]` span — the money
  /// might arrive on this day (spec 5.2).
  ///
  /// Income-driven Spaces only, and that needs no check: a `continuous`
  /// period carries no window at all.
  final bool isUncertainIncome;

  /// A Budget deadline falls here. Hard and soft are drawn differently: solid
  /// against dashed (spec 4.8, 8.1).
  final DeadlineKind? deadline;

  /// Expenses over the threshold (spec 8.1). See [highLoadThreshold].
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

/// Every decoration for the range one view covers.
///
/// Keyed by date, and absent means undecorated: the map holds only the days
/// that carry something.
@immutable
class DayMarks {
  const DayMarks(this._marks, {required this.threshold});

  static const DayMarks empty = DayMarks(
    <CalendarDate, DayMark>{},
    threshold: null,
  );

  final Map<CalendarDate, DayMark> _marks;

  /// The high-load cutoff in force, or null where there is too little history
  /// to set one. Exposed so a screen can say what the mark means.
  final Decimal? threshold;

  DayMark operator [](CalendarDate date) => _marks[date] ?? DayMark.none;
}

/// The decorations for [view] around the selected date.
///
/// One provider for all of it rather than one per decoration: they share the
/// range and the calendar lookup, and a cell needs them together anyway.
///
/// The type is inferred: `flutter_riverpod` does not export
/// `FutureProviderFamily`.
final dayMarksProvider = FutureProvider.family<DayMarks, CalendarView>((
  Ref ref,
  CalendarView view,
) async {
  final Space? space = ref.watch(currentSpaceProvider);
  // The Year view draws none of this — twelve cards carry three figures each —
  // so it does not pay for a walk over 365 days.
  if (space == null || view == CalendarView.year) return DayMarks.empty;

  final CalendarDate around = ref.watch(selectedDateProvider);
  final ({CalendarDate from, CalendarDate to}) range = rangeOf(view, around);

  // The browsed year, not the materialisation horizon: the screen scrolls
  // past it in either direction (spec 8.1).
  final ResolvedCalendar resolved = await ref.watch(
    calendarForYearProvider(around.year).future,
  );
  final WorkingDayCalendar calendar = resolved.calendar;

  final Map<CalendarDate, DayMark> marks = <CalendarDate, DayMark>{};
  DayMark at(CalendarDate date) => marks[date] ?? DayMark.none;

  for (CalendarDate d = range.from; !d.isAfter(range.to); d = d.addDays(1)) {
    if (!calendar.isNonWorkingDay(d)) continue;
    marks[d] = DayMark(
      isNonWorking: true,
      // A weekend is expected; a holiday is the thing worth pointing at.
      isHoliday: !calendar.weekendDays.contains(d.weekday),
    );
  }

  final List<BudgetPeriod> periods =
      ref.watch(spacePeriodsProvider).value ?? const <BudgetPeriod>[];
  for (final BudgetPeriod p in periods) {
    final CalendarDate? start = p.windowStart;
    final CalendarDate? end = p.windowEnd;
    // A one-day window is certain, and hatching it would say otherwise.
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

  // The threshold is read off recent history, not off the range on screen: a
  // quiet month must not lower the bar for what counts as a heavy day.
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
