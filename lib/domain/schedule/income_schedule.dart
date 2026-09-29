import 'package:meta/meta.dart';
import 'package:sielto/domain/schedule/income_window.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// The four schedule types. [baseRangeFor] ignores working days;
/// [resolveFor] applies them.
@immutable
sealed class IncomeSchedule {
  const IncomeSchedule();

  /// A precise schedule returns a null [end].
  ({CalendarDate start, CalendarDate? end}) baseRangeFor(int year, int month);

  IncomeWindow resolveFor(
    int year,
    int month, {
    required WorkingDayCalendar calendar,
  }) {
    final ({CalendarDate? end, CalendarDate start}) base = baseRangeFor(
      year,
      month,
    );
    return resolveIncomeWindow(
      start: base.start,
      end: base.end,
      calendar: calendar,
    );
  }

  static int daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;
}

/// "The 26th of every month". Short months clamp to their last day.
class FixedDateSchedule extends IncomeSchedule {
  const FixedDateSchedule(this.day);

  final int day;

  @override
  ({CalendarDate start, CalendarDate? end}) baseRangeFor(int year, int month) {
    if (day < 1 || day > 31) {
      throw ArgumentError.value(day, 'day', 'outside 1..31');
    }
    final int clamped = day.clamp(1, IncomeSchedule.daysInMonth(year, month));
    return (start: CalendarDate(year, month, clamped), end: null);
  }
}

/// "The last Friday", "the second Wednesday". No fifth: not every month has
/// one.
class WeekdayRuleSchedule extends IncomeSchedule {
  const WeekdayRuleSchedule(this.ordinal, this.weekday);

  final WeekdayOrdinal ordinal;
  final Weekday weekday;

  /// 1 = Monday, as in [DateTime.weekday].
  int get _targetWeekday => weekday.index + 1;

  @override
  ({CalendarDate start, CalendarDate? end}) baseRangeFor(int year, int month) {
    final int length = IncomeSchedule.daysInMonth(year, month);

    if (ordinal == WeekdayOrdinal.last) {
      for (int day = length; day >= 1; day--) {
        final CalendarDate date = CalendarDate(year, month, day);
        if (date.weekday == _targetWeekday) {
          return (start: date, end: null);
        }
      }
    } else {
      final int wanted = ordinal.index + 1;
      int seen = 0;
      for (int day = 1; day <= length; day++) {
        final CalendarDate date = CalendarDate(year, month, day);
        if (date.weekday != _targetWeekday) continue;
        if (++seen == wanted) return (start: date, end: null);
      }
    }

    // Unreachable.
    throw StateError('$ordinal $weekday does not occur in $year-$month');
  }
}

/// "Between the 23rd and the 25th". Anchored on the last working day.
class DateRangeSchedule extends IncomeSchedule {
  const DateRangeSchedule(this.startDay, this.endDay);

  final int startDay;
  final int endDay;

  @override
  ({CalendarDate start, CalendarDate? end}) baseRangeFor(int year, int month) {
    if (startDay < 1 || startDay > 31 || endDay < 1 || endDay > 31) {
      throw ArgumentError('date range $startDay..$endDay is outside 1..31');
    }
    if (endDay < startDay) {
      throw ArgumentError(
        'date range $startDay..$endDay ends before it starts',
      );
    }
    final int length = IncomeSchedule.daysInMonth(year, month);
    return (
      start: CalendarDate(year, month, startDay.clamp(1, length)),
      end: CalendarDate(year, month, endDay.clamp(1, length)),
    );
  }
}

/// "The first three days", "the last three days", against the real month
/// length. At most 15 days.
class BoundaryDaysSchedule extends IncomeSchedule {
  const BoundaryDaysSchedule(this.anchor, this.count);

  static const int maxCount = 15;

  final BoundaryAnchor anchor;
  final int count;

  @override
  ({CalendarDate start, CalendarDate? end}) baseRangeFor(int year, int month) {
    if (count < 1 || count > maxCount) {
      throw ArgumentError.value(count, 'count', 'outside 1..$maxCount');
    }
    final int length = IncomeSchedule.daysInMonth(year, month);
    return switch (anchor) {
      BoundaryAnchor.start => (
        start: CalendarDate(year, month, 1),
        end: CalendarDate(year, month, count.clamp(1, length)),
      ),
      BoundaryAnchor.end => (
        start: CalendarDate(year, month, (length - count + 1).clamp(1, length)),
        end: CalendarDate(year, month, length),
      ),
    };
  }
}
