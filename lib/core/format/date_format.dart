import 'package:intl/intl.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Renders a [CalendarDate] for display.
///
/// A calendar date has no zone, so it is handed to intl as UTC midnight — the
/// arithmetic anchor the type already uses. Any other conversion would risk
/// printing the day before.
class DateLabels {
  DateLabels(this.locale)
    : _dayMonth = DateFormat.MMMMd(locale),
      _dayMonthYear = DateFormat.yMMMMd(locale),
      _weekday = DateFormat.EEEE(locale),
      _weekdayShort = DateFormat.E(locale),
      _monthYear = DateFormat.yMMMM(locale),
      _monthShort = DateFormat.MMM(locale),
      _dayOfMonth = DateFormat.d(locale),
      _short = DateFormat.yMd(locale);

  final String locale;
  final DateFormat _dayMonth;
  final DateFormat _dayMonthYear;
  final DateFormat _weekday;
  final DateFormat _weekdayShort;
  final DateFormat _monthYear;
  final DateFormat _monthShort;
  final DateFormat _dayOfMonth;
  final DateFormat _short;

  /// "14 August". The year is dropped when it matches [reference], which is
  /// almost always the current year.
  String dayMonth(CalendarDate date, {CalendarDate? reference}) {
    final bool sameYear = reference == null || reference.year == date.year;
    final DateFormat format = sameYear ? _dayMonth : _dayMonthYear;
    return format.format(date.toUtcMidnight());
  }

  String weekday(CalendarDate date) => _weekday.format(date.toUtcMidnight());

  /// "Thu". The calendar's column headings and week rows.
  String weekdayShort(CalendarDate date) =>
      _weekdayShort.format(date.toUtcMidnight());

  /// "August 2026". The Month view's navigator.
  String monthYear(CalendarDate date) =>
      _monthYear.format(date.toUtcMidnight());

  /// "Aug". The Year view's twelve cards.
  String monthShort(CalendarDate date) =>
      _monthShort.format(date.toUtcMidnight());

  /// Just the number, so the Month grid does not carry a month name in every
  /// cell.
  String dayOfMonth(CalendarDate date) =>
      _dayOfMonth.format(date.toUtcMidnight());

  /// "Thursday, 24 July". The Day view's navigator.
  String weekdayAndDate(CalendarDate date, {CalendarDate? reference}) =>
      '${weekday(date)}, ${dayMonth(date, reference: reference)}';

  /// "12 – 18 August", collapsing whatever the two ends share.
  ///
  /// Built from the two ends rather than from a pattern: intl has no interval
  /// format, and spelling the month twice is what the design avoids.
  String range(CalendarDate from, CalendarDate to, {CalendarDate? reference}) {
    if (from == to) return dayMonth(from, reference: reference);
    final String end = dayMonth(to, reference: reference);
    if (from.year == to.year && from.month == to.month) {
      return '${dayOfMonth(from)} – $end';
    }
    return '${dayMonth(from, reference: reference)} – $end';
  }

  /// Numeric, for dense contexts.
  String short(CalendarDate date) => _short.format(date.toUtcMidnight());
}
