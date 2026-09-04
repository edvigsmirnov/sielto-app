import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';

/// The ranges every Calendar view is built from.
///
/// Off-by-one here is invisible on screen — a grid still draws — but silently
/// drops a day's figures or queries a month too few.
void main() {
  group('startOfWeek', () {
    test('a Monday is its own week start', () {
      const CalendarDate monday = CalendarDate(2026, 8, 10);
      expect(monday.weekday, DateTime.monday);
      expect(monday.startOfWeek, monday);
    });

    test('a Sunday belongs to the week that began six days earlier', () {
      const CalendarDate sunday = CalendarDate(2026, 8, 16);
      expect(sunday.weekday, DateTime.sunday);
      expect(sunday.startOfWeek, const CalendarDate(2026, 8, 10));
    });

    test('crosses a month boundary backwards', () {
      // 1 September 2026 is a Tuesday, so its week opens in August.
      expect(
        const CalendarDate(2026, 9, 1).startOfWeek,
        const CalendarDate(2026, 8, 31),
      );
    });
  });

  group('month bounds', () {
    test('February knows its own length in a leap year and out of one', () {
      expect(const CalendarDate(2028, 2, 15).daysInMonth, 29);
      expect(const CalendarDate(2026, 2, 15).daysInMonth, 28);
    });

    test('the last of December does not roll into January', () {
      expect(
        const CalendarDate(2026, 12, 5).lastOfMonth,
        const CalendarDate(2026, 12, 31),
      );
    });
  });

  group('rangeOf', () {
    test('a day is its own range', () {
      const CalendarDate d = CalendarDate(2026, 8, 14);
      expect(rangeOf(CalendarView.day, d), (from: d, to: d));
    });

    test('a week is seven days from Monday', () {
      final ({CalendarDate from, CalendarDate to}) week = rangeOf(
        CalendarView.week,
        const CalendarDate(2026, 8, 14),
      );
      expect(week.from, const CalendarDate(2026, 8, 10));
      expect(week.to, const CalendarDate(2026, 8, 16));
      expect(week.from.daysUntil(week.to), 6);
    });

    test('the month grid is always six whole weeks', () {
      for (int month = 1; month <= 12; month++) {
        final ({CalendarDate from, CalendarDate to}) grid = rangeOf(
          CalendarView.month,
          CalendarDate(2026, month, 1),
        );
        expect(grid.from.weekday, DateTime.monday, reason: 'month $month');
        expect(
          grid.from.daysUntil(grid.to),
          monthGridDays - 1,
          reason: 'month $month',
        );
      }
    });

    test('the month grid covers every day of its month', () {
      // The reason the range is the grid and not the calendar month: the
      // neighbouring cells carry figures too, and a range clipped to the month
      // would draw them empty.
      for (int month = 1; month <= 12; month++) {
        final CalendarDate first = CalendarDate(2026, month, 1);
        final ({CalendarDate from, CalendarDate to}) grid = rangeOf(
          CalendarView.month,
          first,
        );
        expect(grid.from.isAfter(first), isFalse, reason: 'month $month');
        expect(
          grid.to.isBefore(first.lastOfMonth),
          isFalse,
          reason: 'month $month',
        );
      }
    });

    test('a year runs 1 January to 31 December', () {
      expect(rangeOf(CalendarView.year, const CalendarDate(2026, 7, 4)), (
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 12, 31),
      ));
    });
  });
}
