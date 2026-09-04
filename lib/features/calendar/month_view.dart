import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_cell.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/day_marks.dart';

/// The Month grid (spec 8.1).
///
/// Aggregate sums only — no payment or category names, which is what keeps it a
/// calendar rather than a second Feed. Tapping a cell opens the Day view;
/// holding one opens the quick-add menu.
///
/// Six fixed rows filling the available height, so the tiles are large enough
/// to read at a glance (spec 8.1) and the grid does not resize between months.
class MonthView extends StatelessWidget {
  const MonthView({
    required this.month,
    required this.selected,
    required this.totals,
    required this.marks,
    required this.today,
    required this.money,
    required this.dates,
    required this.onOpenDay,
    required this.onHoldDay,
    super.key,
  });

  /// Any date in the month being drawn.
  final CalendarDate month;

  /// The shared selected date, which the accent fill marks.
  final CalendarDate selected;

  final Map<CalendarDate, DayTotals> totals;
  final DayMarks marks;
  final CalendarDate today;
  final MoneyFormat money;
  final DateLabels dates;
  final ValueChanged<CalendarDate> onOpenDay;
  final void Function(CalendarDate date, Offset at) onHoldDay;

  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final CalendarDate first = rangeOf(CalendarView.month, month).from;
    return Column(
      children: <Widget>[
        _WeekdayHeader(first: first, dates: dates),
        const SizedBox(height: SageSpace.xs),
        for (int week = 0; week < monthGridDays ~/ 7; week++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: Row(
                children: <Widget>[
                  for (int weekday = 0; weekday < 7; weekday++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: _gap),
                        child: _cell(first.addDays(week * 7 + weekday)),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _cell(CalendarDate date) => _DayCell(
    date: date,
    totals: totals[date],
    mark: marks[date],
    isSelected: date == selected,
    isToday: date == today,
    isOutsideMonth: !date.isSameMonth(month),
    money: money,
    onTap: () => onOpenDay(date),
    onHold: (Offset at) => onHoldDay(date, at),
  );
}

/// Mon-Sun, with the weekend columns in the warning accent (design section 7).
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.first, required this.dates});

  /// The first cell of the grid, which is always a Monday — the labels are read
  /// off real dates so they follow the interface language.
  final CalendarDate first;

  final DateLabels dates;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Row(
      children: <Widget>[
        for (int i = 0; i < 7; i++)
          Expanded(
            child: Text(
              dates.weekdayShort(first.addDays(i)).toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: i >= 5 ? sage.warningAccent : sage.inkLabel,
              ),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.totals,
    required this.mark,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideMonth,
    required this.money,
    required this.onTap,
    required this.onHold,
  });

  final CalendarDate date;
  final DayTotals? totals;
  final DayMark mark;
  final bool isSelected;
  final bool isToday;
  final bool isOutsideMonth;
  final MoneyFormat money;
  final VoidCallback onTap;
  final ValueChanged<Offset> onHold;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DayTotals? day = totals;
    final Color ink = CellDecoration.inkOf(sage, mark, isSelected: isSelected);

    return GestureDetector(
      onTap: onTap,
      // The position is carried through so the menu opens under the finger
      // rather than at the corner of the grid.
      onLongPressStart: (LongPressStartDetails d) => onHold(d.globalPosition),
      child: CellDecoration(
        mark: mark,
        isSelected: isSelected,
        dimmed: isOutsideMonth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              date.day.toString(),
              style: text.labelMedium?.copyWith(
                // Today is the accent ink where it is not the selected cell:
                // the fill is the selection, and one cell must not claim both.
                color: !isSelected && isToday ? sage.accentStrong : ink,
                fontWeight: isSelected || isToday
                    ? FontWeight.w700
                    : FontWeight.w600,
              ),
            ),
            if (day != null && day.expenses > Decimal.zero)
              _CellFigure(
                text: money.shortSigned(-day.expenses),
                color: isSelected ? ink : sage.danger,
              ),
            if (day != null && day.income > Decimal.zero)
              _CellFigure(
                text: money.shortSigned(day.income),
                color: isSelected ? ink : sage.accentStrong,
              ),
            // A day whose only record is a floating income has no figure to
            // draw, and drawing nothing would read as an empty day (spec 4.7).
            if (day != null &&
                day.expenses == Decimal.zero &&
                day.income == Decimal.zero)
              _CellFigure(text: '·', color: isSelected ? ink : sage.inkLabel),
          ],
        ),
      ),
    );
  }
}

/// One figure inside a Month cell: small, and tabular so a column lines up.
class _CellFigure extends StatelessWidget {
  const _CellFigure({required this.text, required this.color});

  final String text;
  final Color color;

  static const double _size = 10;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.clip,
    style: TextStyle(
      fontSize: _size,
      fontWeight: FontWeight.w600,
      color: color,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    ),
  );
}
