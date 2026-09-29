import 'package:sielto/domain/value/calendar_date.dart';

enum RecurrenceInterval { monthly, weekly }

/// Months an open-ended series materialises ahead of today.
const int recurrenceHorizonMonths = 24;

/// [count] includes the first occurrence. Null fills [recurrenceHorizonMonths].
List<CalendarDate> recurrenceDates({
  required CalendarDate start,
  required RecurrenceInterval interval,
  int? count,
}) {
  final CalendarDate horizon = start.addMonths(recurrenceHorizonMonths);
  final List<CalendarDate> dates = <CalendarDate>[];

  CalendarDate current = start;
  int index = 0;
  while (count == null ? !current.isAfter(horizon) : index < count) {
    dates.add(current);
    index++;
    current = switch (interval) {
      // Counted from the start date, so the 31st returns after a short month.
      RecurrenceInterval.monthly => start.addMonths(index),
      RecurrenceInterval.weekly => start.addDays(7 * index),
    };
  }

  return dates;
}
