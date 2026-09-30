import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_cell.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/day_marks.dart';
import 'package:sielto/features/calendar/month_view.dart';

/// Month grid from plain values; no database.
void main() {
  const CalendarDate august = CalendarDate(2026, 8, 14);
  const CalendarDate today = CalendarDate(2026, 8, 14);

  final MoneyFormat money = MoneyFormat(locale: 'en', currencyCode: 'EUR');
  late final DateLabels dates;

  // No localization delegate here, so intl needs initialising.
  setUpAll(() {
    initializeDateFormatting();
    dates = DateLabels('en');
  });

  Future<CalendarDate?> pumpMonth(
    WidgetTester tester, {
    Map<CalendarDate, DayTotals> totals = const <CalendarDate, DayTotals>{},
    DayMarks marks = DayMarks.empty,
    CalendarDate selected = august,
  }) async {
    CalendarDate? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: SageTheme.light,
        home: Scaffold(
          body: MonthView(
            month: august,
            selected: selected,
            totals: totals,
            marks: marks,
            today: today,
            money: money,
            dates: dates,
            onOpenDay: (CalendarDate date) => opened = date,
            onHoldDay: (CalendarDate _, Offset _) {},
          ),
        ),
      ),
    );
    return opened;
  }

  testWidgets('draws six whole weeks of cells', (WidgetTester tester) async {
    await pumpMonth(tester);
    expect(find.byType(CellDecoration), findsNWidgets(monthGridDays));
  });

  testWidgets('starts on the Monday before the first of the month', (
    WidgetTester tester,
  ) async {
    await pumpMonth(tester);
    // August 2026 starts on a Saturday; the first cell is 27 July.
    final Rect first = tester.getRect(find.byType(CellDecoration).first);
    final Rect twentySeven = tester.getRect(find.text('27').first);
    expect(first.contains(twentySeven.center), isTrue);
  });

  testWidgets('every day of the month has a cell', (WidgetTester tester) async {
    await pumpMonth(tester);
    for (int day = 1; day <= 31; day++) {
      expect(
        find.text(day.toString()),
        findsWidgets,
        reason: 'August $day is missing',
      );
    }
  });

  testWidgets('a day with figures draws them, signed', (
    WidgetTester tester,
  ) async {
    await pumpMonth(
      tester,
      totals: <CalendarDate, DayTotals>{
        const CalendarDate(2026, 8, 12): DayTotals.empty.add(
          Decimal.parse('22'),
          isIncome: false,
          isPaid: false,
          amountKnown: true,
        ),
        const CalendarDate(2026, 8, 27): DayTotals.empty.add(
          Decimal.parse('3224'),
          isIncome: true,
          isPaid: false,
          amountKnown: true,
        ),
      },
    );

    expect(find.textContaining('−').at(0), findsOneWidget);
    expect(find.textContaining('22'), findsWidgets);
    expect(find.textContaining('+'), findsOneWidget);
  });

  testWidgets('a day with a record but no figure still shows something', (
    WidgetTester tester,
  ) async {
    await pumpMonth(
      tester,
      totals: <CalendarDate, DayTotals>{
        const CalendarDate(2026, 8, 27): DayTotals.empty.add(
          Decimal.zero,
          isIncome: true,
          isPaid: false,
          amountKnown: false,
        ),
      },
    );
    expect(find.text('·'), findsOneWidget);
  });

  testWidgets('tapping a cell reports its date', (WidgetTester tester) async {
    CalendarDate? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: SageTheme.light,
        home: Scaffold(
          body: MonthView(
            month: august,
            selected: august,
            totals: const <CalendarDate, DayTotals>{},
            marks: DayMarks.empty,
            today: today,
            money: money,
            dates: dates,
            onOpenDay: (CalendarDate date) => opened = date,
            onHoldDay: (CalendarDate _, Offset _) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('20'));
    expect(opened, const CalendarDate(2026, 8, 20));
  });

  testWidgets('today takes the accent fill, the selection an outline', (
    WidgetTester tester,
  ) async {
    await pumpMonth(tester, selected: const CalendarDate(2026, 8, 20));

    final SageColors sage = SageColors.light;
    final List<CellDecoration> cells = tester
        .widgetList<CellDecoration>(find.byType(CellDecoration))
        .toList();
    final CellDecoration filled = cells.singleWhere(
      (CellDecoration c) => c.isToday,
    );
    final CellDecoration outlined = cells.singleWhere(
      (CellDecoration c) => c.isSelected,
    );
    expect(filled, isNot(outlined));
    expect(
      CellDecoration.groundOf(sage, filled.mark, isToday: true),
      sage.accent,
    );
    expect(
      CellDecoration.groundOf(sage, outlined.mark, isToday: false),
      sage.card,
    );
  });

  testWidgets('a non-working day is washed and a holiday gains a dot', (
    WidgetTester tester,
  ) async {
    const CalendarDate saturday = CalendarDate(2026, 8, 15);
    const CalendarDate holiday = CalendarDate(2026, 8, 17);
    await pumpMonth(
      tester,
      // Not const: CalendarDate overrides `==`.
      marks: DayMarks(<CalendarDate, DayMark>{
        saturday: const DayMark(isNonWorking: true),
        holiday: const DayMark(isNonWorking: true, isHoliday: true),
      }, threshold: null),
    );

    final SageColors sage = SageColors.light;
    final List<CellDecoration> washed = tester
        .widgetList<CellDecoration>(find.byType(CellDecoration))
        .where((CellDecoration c) => c.mark.isNonWorking)
        .toList();
    expect(washed.length, 2);
    for (final CellDecoration cell in washed) {
      expect(
        CellDecoration.groundOf(sage, cell.mark, isToday: false),
        sage.warningTint,
      );
    }
    expect(
      washed.where((CellDecoration c) => c.mark.isHoliday).length,
      1,
      reason: 'the weekend gets the wash, only the holiday gets the dot',
    );
  });

  testWidgets('days outside the month are dimmed, not hidden', (
    WidgetTester tester,
  ) async {
    await pumpMonth(tester);
    final int dimmed = tester
        .widgetList<CellDecoration>(find.byType(CellDecoration))
        .where((CellDecoration c) => c.dimmed)
        .length;
    // 5 days of July and 6 of September.
    expect(dimmed, monthGridDays - 31);
  });
}
