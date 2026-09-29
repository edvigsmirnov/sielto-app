import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_cell.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/day_marks.dart';

/// Month grid of sums. Tap opens the Day view; long-press opens the menu.
/// Six rows fill the height.
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

  /// Any date in the month.
  final CalendarDate month;

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

/// Weekend columns in `warningAccent`.
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.first, required this.dates});

  /// Always a Monday. Labels come from real dates, in the interface language.
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
    final Color ink = CellDecoration.inkOf(sage, mark, isToday: isToday);

    return GestureDetector(
      onTap: onTap,
      // Opens the menu at the finger.
      onLongPressStart: (LongPressStartDetails d) {
        HapticFeedback.mediumImpact();
        onHold(d.globalPosition);
      },
      child: CellDecoration(
        mark: mark,
        isSelected: isSelected,
        isToday: isToday,
        dimmed: isOutsideMonth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              date.day.toString(),
              style: text.labelMedium?.copyWith(
                color: ink,
                fontWeight: isSelected || isToday
                    ? FontWeight.w700
                    : FontWeight.w600,
              ),
            ),
            if (day != null && day.expenses > Decimal.zero)
              _CellFigure(
                text: money.shortSigned(-day.expenses),
                color: isToday ? ink : sage.danger,
              ),
            if (day != null && day.income > Decimal.zero)
              _CellFigure(
                text: money.shortSigned(day.income),
                color: isToday ? ink : sage.accentStrong,
              ),
            // A dot for a day with only an income without amount.
            if (day != null &&
                day.expenses == Decimal.zero &&
                day.income == Decimal.zero)
              _CellFigure(text: '·', color: isToday ? ink : sage.inkLabel),
          ],
        ),
      ),
    );
  }
}

/// Small tabular figure.
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
