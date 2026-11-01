import 'package:meta/meta.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// When an income may land, and the anchor date the calculations use. The
/// anchor moves forward to a working day, but never into the next month.
@immutable
class IncomeWindow {
  const IncomeWindow({
    required this.windowStart,
    required this.windowEnd,
    required this.anchorDate,
  });

  /// Earliest possible arrival.
  final CalendarDate windowStart;

  /// Latest possible arrival. Always a working day.
  final CalendarDate windowEnd;

  /// Last working day of the window, or the first one when the last is in the
  /// next month.
  final CalendarDate anchorDate;

  /// True for a span or a base date on a non-working day.
  bool get isUncertain => windowStart != windowEnd;

  int get lengthInDays => windowStart.daysUntil(windowEnd) + 1;

  @override
  bool operator ==(Object other) =>
      other is IncomeWindow &&
      other.windowStart == windowStart &&
      other.windowEnd == windowEnd &&
      other.anchorDate == anchorDate;

  @override
  int get hashCode => Object.hash(windowStart, windowEnd, anchorDate);

  @override
  String toString() =>
      'IncomeWindow($windowStart..$windowEnd, anchor $anchorDate)';
}

/// A precise [start] on a non-working day widens to the working days on both
/// sides. A span keeps its [start] and extends right, or left too when every
/// day of it is off and the anchor falls back before it.
IncomeWindow resolveIncomeWindow({
  required CalendarDate start,
  required WorkingDayCalendar calendar,
  CalendarDate? end,
}) {
  if (end == null) {
    if (calendar.isWorkingDay(start)) {
      return IncomeWindow(
        windowStart: start,
        windowEnd: start,
        anchorDate: start,
      );
    }
    final CalendarDate before = calendar.workingDayOnOrBefore(start);
    final CalendarDate after = calendar.workingDayOnOrAfter(start);
    return IncomeWindow(
      windowStart: before,
      windowEnd: after,
      anchorDate: _anchorWithin(start, before: before, after: after),
    );
  }

  if (end.isBefore(start)) {
    throw ArgumentError.value(end, 'end', 'ends before $start');
  }
  final CalendarDate windowEnd = calendar.workingDayOnOrAfter(end);
  final CalendarDate anchor = _anchorWithin(
    end,
    before: calendar.workingDayOnOrBefore(end),
    after: windowEnd,
  );
  return IncomeWindow(
    windowStart: anchor.isBefore(start) ? anchor : start,
    windowEnd: windowEnd,
    anchorDate: anchor,
  );
}

/// Forward, unless that leaves the month of [scheduled].
CalendarDate _anchorWithin(
  CalendarDate scheduled, {
  required CalendarDate before,
  required CalendarDate after,
}) => after.isSameMonth(scheduled) ? after : before;
