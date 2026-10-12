import 'package:intl/intl.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Formats [CalendarDate]s. Dates go to intl as UTC midnight.
class DateLabels {
  DateLabels(this.locale)
    : _dayMonth = DateFormat.MMMMd(locale),
      _dayMonthYear = DateFormat.yMMMMd(locale),
      _weekday = DateFormat.EEEE(locale),
      _weekdayShort = DateFormat.E(locale),
      _monthYear = DateFormat.yMMMM(locale),
      _monthShort = DateFormat.MMM(locale),
      _dayMonthShort = DateFormat.MMMd(locale),
      _dayOfMonth = DateFormat.d(locale),
      _short = DateFormat.yMd(locale);

  final String locale;
  final DateFormat _dayMonth;
  final DateFormat _dayMonthYear;
  final DateFormat _weekday;
  final DateFormat _weekdayShort;
  final DateFormat _monthYear;
  final DateFormat _monthShort;
  final DateFormat _dayMonthShort;
  final DateFormat _dayOfMonth;
  final DateFormat _short;

  /// "14 August". No year when it matches [reference].
  String dayMonth(CalendarDate date, {CalendarDate? reference}) {
    final bool sameYear = reference == null || reference.year == date.year;
    final DateFormat format = sameYear ? _dayMonth : _dayMonthYear;
    return format.format(date.toUtcMidnight());
  }

  /// "14 August 2026".
  String full(CalendarDate date) => _dayMonthYear.format(date.toUtcMidnight());

  String weekday(CalendarDate date) => _weekday.format(date.toUtcMidnight());

  /// "Thu".
  String weekdayShort(CalendarDate date) =>
      _weekdayShort.format(date.toUtcMidnight());

  /// "August 2026".
  String monthYear(CalendarDate date) =>
      _monthYear.format(date.toUtcMidnight());

  /// "Aug".
  String monthShort(CalendarDate date) =>
      _monthShort.format(date.toUtcMidnight());

  /// "Aug 14".
  String dayMonthShort(CalendarDate date) =>
      _dayMonthShort.format(date.toUtcMidnight());

  /// Day number only.
  String dayOfMonth(CalendarDate date) =>
      _dayOfMonth.format(date.toUtcMidnight());

  /// "Thursday, 24 July".
  String weekdayAndDate(CalendarDate date, {CalendarDate? reference}) =>
      '${weekday(date)}, ${dayMonth(date, reference: reference)}';

  /// "12 – 18 August" or "August 12 – 18", sharing the common parts. intl has
  /// no interval format.
  String range(CalendarDate from, CalendarDate to, {CalendarDate? reference}) {
    if (from == to) return dayMonth(from, reference: reference);
    final String end = dayMonth(to, reference: reference);
    if (from.year == to.year && from.month == to.month) {
      if (_dayMonth.pattern?.startsWith('d') ?? true) {
        return '${dayOfMonth(from)} – $end';
      }
      // Month first: "August 12 – 18", the year after the last day.
      final bool withYear = reference != null && reference.year != to.year;
      return '${_dayMonth.format(from.toUtcMidnight())} – ${dayOfMonth(to)}'
          '${withYear ? ', ${to.year}' : ''}';
    }
    return '${dayMonth(from, reference: reference)} – $end';
  }

  /// Numeric.
  String short(CalendarDate date) => _short.format(date.toUtcMidnight());
}
