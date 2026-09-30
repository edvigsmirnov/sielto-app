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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final _Figures figures = _Figures.fit(
          context,
          days: <DayTotals>[
            for (int i = 0; i < monthGridDays; i++)
              if (totals[first.addDays(i)] case final DayTotals t) t,
          ],
          money: money,
          width: constraints.maxWidth / 7 - _gap - 2 * _cellInset,
        );
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
                            child: _cell(
                              first.addDays(week * 7 + weekday),
                              figures,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static const double _cellInset = 2;

  Widget _cell(CalendarDate date, _Figures figures) => _DayCell(
    date: date,
    totals: totals[date],
    mark: marks[date],
    isSelected: date == selected,
    isToday: date == today,
    isOutsideMonth: !date.isSameMonth(month),
    figures: figures,
    onTap: () => onOpenDay(date),
    onHold: (Offset at) => onHoldDay(date, at),
  );
}

/// One size for the month's figures, fitted to the widest; figures too wide
/// even at [_minSize] are shortened.
class _Figures {
  const _Figures({
    required this.money,
    required this.size,
    required this.shortened,
  });

  factory _Figures.fit(
    BuildContext context, {
    required List<DayTotals> days,
    required MoneyFormat money,
    required double width,
  }) {
    final TextPainter painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    try {
      double widest = 0;
      final Set<Decimal> shortened = <Decimal>{};
      for (final DayTotals d in days) {
        for (final Decimal a in <Decimal>[d.expenses, d.income]) {
          if (a <= Decimal.zero) continue;
          painter
            ..text = TextSpan(text: money.bare(a), style: _style(_maxSize))
            ..layout();
          if (painter.width * _minSize / _maxSize > width) {
            shortened.add(a);
          } else if (painter.width > widest) {
            widest = painter.width;
          }
        }
      }
      final double size = widest <= width
          ? _maxSize
          : (_maxSize * width / widest).clamp(_minSize, _maxSize);
      return _Figures(money: money, size: size, shortened: shortened);
    } finally {
      painter.dispose();
    }
  }

  final MoneyFormat money;
  final double size;
  final Set<Decimal> shortened;

  String format(Decimal amount) => shortened.contains(amount)
      ? money.bareCompact(amount)
      : money.bare(amount);

  static const double _maxSize = 10;
  static const double _minSize = 8;

  static TextStyle _style(double size) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w600,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
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
    required this.figures,
    required this.onTap,
    required this.onHold,
  });

  final CalendarDate date;
  final DayTotals? totals;
  final DayMark mark;
  final bool isSelected;
  final bool isToday;
  final bool isOutsideMonth;
  final _Figures figures;
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
                text: figures.format(day.expenses),
                size: figures.size,
                color: isToday ? ink : sage.danger,
              ),
            if (day != null && day.income > Decimal.zero)
              _CellFigure(
                text: figures.format(day.income),
                size: figures.size,
                color: isToday ? ink : sage.accentStrong,
              ),
            // A dot for a day with only an income without amount.
            if (day != null &&
                day.expenses == Decimal.zero &&
                day.income == Decimal.zero)
              _CellFigure(
                text: '·',
                size: figures.size,
                color: isToday ? ink : sage.inkLabel,
              ),
          ],
        ),
      ),
    );
  }
}

/// Small tabular figure.
class _CellFigure extends StatelessWidget {
  const _CellFigure({
    required this.text,
    required this.size,
    required this.color,
  });

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.clip,
    style: _Figures._style(size).copyWith(color: color),
  );
}
