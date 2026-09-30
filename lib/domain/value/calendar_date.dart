import 'package:meta/meta.dart';

/// A calendar day with no time and no zone. See `SpaceClock` for "today".
@immutable
class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  /// Normalises out-of-range values: 2026-02-30 is 2026-03-02.
  factory CalendarDate.from(int year, int month, int day) {
    final DateTime d = DateTime.utc(year, month, day);
    return CalendarDate(d.year, d.month, d.day);
  }

  /// Parses `YYYY-MM-DD` only, and only real days.
  factory CalendarDate.parse(String iso) {
    final Match? m = _isoPattern.firstMatch(iso);
    if (m == null) {
      throw FormatException('expected YYYY-MM-DD', iso);
    }
    final CalendarDate date = CalendarDate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    if (CalendarDate.from(date.year, date.month, date.day) != date) {
      throw FormatException('no such day', iso);
    }
    return date;
  }

  /// Uses the year, month and day as they read on [dateTime], in its own zone.
  factory CalendarDate.fromDateTime(DateTime dateTime) =>
      CalendarDate(dateTime.year, dateTime.month, dateTime.day);

  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  /// `YYYY-MM-DD`; sorts lexicographically.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Arithmetic anchor only.
  DateTime toUtcMidnight() => DateTime.utc(year, month, day);

  CalendarDate addDays(int days) {
    final DateTime d = toUtcMidnight().add(Duration(days: days));
    return CalendarDate(d.year, d.month, d.day);
  }

  /// Clamps to the target month: 31 January plus one month is 28 or 29 February.
  CalendarDate addMonths(int months) {
    final int total = year * 12 + (month - 1) + months;
    final int targetYear = total ~/ 12;
    final int targetMonth = total % 12 + 1;
    final int lastDay = CalendarDate.from(
      targetYear,
      targetMonth + 1,
      1,
    ).addDays(-1).day;
    return CalendarDate(targetYear, targetMonth, day > lastDay ? lastDay : day);
  }

  /// Negative when [other] is earlier.
  int daysUntil(CalendarDate other) =>
      other.toUtcMidnight().difference(toUtcMidnight()).inDays;

  /// 1 = Monday through 7 = Sunday.
  int get weekday => toUtcMidnight().weekday;

  CalendarDate get firstOfMonth => CalendarDate(year, month, 1);

  CalendarDate get lastOfMonth =>
      CalendarDate.from(year, month + 1, 1).addDays(-1);

  int get daysInMonth => lastOfMonth.day;

  /// Weeks start on Monday regardless of locale.
  CalendarDate get startOfWeek => addDays(1 - weekday);

  bool isSameMonth(CalendarDate other) =>
      year == other.year && month == other.month;

  bool isBefore(CalendarDate other) => compareTo(other) < 0;

  bool isAfter(CalendarDate other) => compareTo(other) > 0;

  @override
  int compareTo(CalendarDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
