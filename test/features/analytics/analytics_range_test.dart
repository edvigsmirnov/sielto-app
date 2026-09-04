import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/analytics/analytics_range.dart';

/// The calendar ranges Analytics reads over (spec 8.2).
///
/// Bounds derived from an anchor rather than stored, so stepping cannot drift.
void main() {
  AnalyticsRange range(RangeUnit unit, CalendarDate anchor) =>
      AnalyticsRange(unit: unit, anchor: anchor);

  group('month', () {
    test('spans the whole calendar month', () {
      final AnalyticsRange r = range(
        RangeUnit.month,
        const CalendarDate(2026, 8, 14),
      );
      expect(r.from, const CalendarDate(2026, 8, 1));
      expect(r.to, const CalendarDate(2026, 8, 31));
    });

    test('February knows its own length', () {
      expect(
        range(RangeUnit.month, const CalendarDate(2028, 2, 14)).to,
        const CalendarDate(2028, 2, 29),
      );
    });

    test('stepping from the 31st does not skip a month', () {
      // The bug this guards: addMonths on the 31st clamps, and stepping an
      // anchor that had already clamped would land two months on. The step
      // normalises to the first before it moves.
      AnalyticsRange r = range(
        RangeUnit.month,
        const CalendarDate(2026, 1, 31),
      );
      final List<int> months = <int>[];
      for (int i = 0; i < 4; i++) {
        r = r.step(1);
        months.add(r.from.month);
      }
      expect(months, <int>[2, 3, 4, 5]);
    });

    test('stepping back crosses a year boundary', () {
      final AnalyticsRange r = range(
        RangeUnit.month,
        const CalendarDate(2026, 1, 15),
      ).step(-1);
      expect(r.from, const CalendarDate(2025, 12, 1));
      expect(r.to, const CalendarDate(2025, 12, 31));
    });
  });

  group('quarter', () {
    test('snaps to the quarter the anchor falls in', () {
      for (final (int month, int first) in const <(int, int)>[
        (1, 1),
        (3, 1),
        (4, 4),
        (6, 4),
        (7, 7),
        (9, 7),
        (10, 10),
        (12, 10),
      ]) {
        final AnalyticsRange r = range(
          RangeUnit.quarter,
          CalendarDate(2026, month, 15),
        );
        expect(r.from.month, first, reason: 'month $month');
      }
    });

    test('runs three whole months', () {
      final AnalyticsRange r = range(
        RangeUnit.quarter,
        const CalendarDate(2026, 8, 14),
      );
      expect(r.from, const CalendarDate(2026, 7, 1));
      expect(r.to, const CalendarDate(2026, 9, 30));
    });

    test('stepping moves a quarter, not a month', () {
      final AnalyticsRange r = range(
        RangeUnit.quarter,
        const CalendarDate(2026, 8, 14),
      ).step(1);
      expect(r.from, const CalendarDate(2026, 10, 1));
      expect(r.to, const CalendarDate(2026, 12, 31));
    });

    test('four steps make a year', () {
      AnalyticsRange r = range(
        RangeUnit.quarter,
        const CalendarDate(2026, 2, 3),
      );
      for (int i = 0; i < 4; i++) {
        r = r.step(1);
      }
      expect(r.from, const CalendarDate(2027, 1, 1));
    });
  });

  group('year', () {
    test('spans January to December', () {
      final AnalyticsRange r = range(
        RangeUnit.year,
        const CalendarDate(2026, 8, 14),
      );
      expect(r.from, const CalendarDate(2026, 1, 1));
      expect(r.to, const CalendarDate(2026, 12, 31));
    });

    test('stepping moves a whole year', () {
      expect(
        range(RangeUnit.year, const CalendarDate(2026, 8, 14)).step(-2).from,
        const CalendarDate(2024, 1, 1),
      );
    });
  });

  test('changing the unit keeps the anchor', () {
    // The point of the anchor: switching from March to the quarter shows the
    // quarter March is in, not the first of the year.
    final AnalyticsRange month = range(
      RangeUnit.month,
      const CalendarDate(2026, 3, 20),
    );
    final AnalyticsRange quarter = month.withUnit(RangeUnit.quarter);
    expect(quarter.from, const CalendarDate(2026, 1, 1));
    expect(quarter.to, const CalendarDate(2026, 3, 31));
  });

  test('no unit exceeds a year, so the isolate arm never fires on span', () {
    // Spec 8.2 names ">1 year" as one arm of the isolate threshold; with these
    // units it is unreachable and the row count decides alone.
    for (final RangeUnit unit in RangeUnit.values) {
      expect(
        range(unit, const CalendarDate(2026, 8, 14)).exceedsAYear,
        isFalse,
        reason: unit.name,
      );
    }
  });
}
