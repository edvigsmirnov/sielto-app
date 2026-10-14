import 'package:meta/meta.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Non-working days: weekends, public holidays and user-marked days.
@immutable
class WorkingDayCalendar {
  WorkingDayCalendar({
    Set<CalendarDate> holidays = const <CalendarDate>{},
    Set<CalendarDate> customNonWorkingDays = const <CalendarDate>{},
    this.weekendDays = defaultWeekend,
  }) : _nonWorking = <CalendarDate>{...holidays, ...customNonWorkingDays};

  const WorkingDayCalendar._(this._nonWorking, this.weekendDays);

  /// Saturday and Sunday, in [DateTime.weekday] numbering.
  static const Set<int> defaultWeekend = <int>{
    DateTime.saturday,
    DateTime.sunday,
  };

  factory WorkingDayCalendar.weekendsOnly() => WorkingDayCalendar();

  final Set<CalendarDate> _nonWorking;
  final Set<int> weekendDays;

  /// The same days off, with [weekday] (as in [DateTime.weekday]) worked.
  WorkingDayCalendar working(int weekday) =>
      WorkingDayCalendar._(_nonWorking, <int>{...weekendDays}..remove(weekday));

  bool isWorkingDay(CalendarDate date) =>
      !weekendDays.contains(date.weekday) && !_nonWorking.contains(date);

  bool isNonWorkingDay(CalendarDate date) => !isWorkingDay(date);

  /// A holiday or user-marked day, whatever the weekday.
  bool isDayOff(CalendarDate date) => _nonWorking.contains(date);

  CalendarDate workingDayOnOrBefore(CalendarDate date) =>
      _search(date, step: -1);

  CalendarDate workingDayOnOrAfter(CalendarDate date) => _search(date, step: 1);

  /// [maxSteps] guards against a malformed holiday set.
  CalendarDate _search(CalendarDate from, {required int step}) {
    const int maxSteps = 60;
    CalendarDate candidate = from;
    for (int i = 0; i <= maxSteps; i++) {
      if (isWorkingDay(candidate)) return candidate;
      candidate = candidate.addDays(step);
    }
    throw StateError(
      'no working day within $maxSteps days of $from; '
      'the holiday set is almost certainly wrong',
    );
  }
}
