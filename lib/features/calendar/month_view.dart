import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/layout.dart';
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

  /// Narrower cells show one figure a day: income less spending.
  static const double _netBelow = 72;

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
          net: constraints.maxWidth / 7 < _netBelow,
        );
        return Column(
          children: <Widget>[
            // Each cell says its weekday.
            ExcludeSemantics(
              child: _WeekdayHeader(first: first, dates: dates),
            ),
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

  /// Tall enough for 48 dp day cells under the weekday names, at any text
  /// size.
  static double minHeight(BuildContext context) {
    final TextStyle? names = Theme.of(context).textTheme.labelSmall;
    final double line = MediaQuery.textScalerOf(context)
        .scale((names?.fontSize ?? 11) * (names?.height ?? 1.5));
    return line +
        SageSpace.xs +
        monthGridDays ~/
            7 *
            (kMinInteractiveDimension + _gap + 2 * _cellInset + 1);
  }

  Widget _cell(CalendarDate date, _Figures figures) => _DayCell(
    date: date,
    totals: totals[date],
    mark: marks[date],
    isSelected: date == selected,
    isToday: date == today,
    isOutsideMonth: !date.isSameMonth(month),
    label: describeDay(
      date,
      totals: totals[date],
      mark: marks[date],
      today: today,
      money: money,
      dates: dates,
    ),
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
    required this.net,
  });

  factory _Figures.fit(
    BuildContext context, {
    required List<DayTotals> days,
    required MoneyFormat money,
    required double width,
    required bool net,
  }) {
    final double maxSize = desktopInput ? _maxDesktop : _maxSize;
    double widest = 0;
    final Set<Decimal> shortened = <Decimal>{};
    for (final DayTotals d in days) {
      for (final Decimal a
          in net
              ? <Decimal>[(d.income - d.expenses).abs()]
              : <Decimal>[d.expenses, d.income]) {
        if (a <= Decimal.zero) continue;
        final double w = textWidth(
          context,
          '−${money.bare(a)}',
          _style(maxSize),
        );
        if (w * _minSize / maxSize > width) {
          shortened.add(a);
        } else if (w > widest) {
          widest = w;
        }
      }
    }
    final double size = widest <= width
        ? maxSize
        : (maxSize * width / widest).clamp(_minSize, maxSize);
    return _Figures(money: money, size: size, shortened: shortened, net: net);
  }

  final MoneyFormat money;
  final double size;
  final Set<Decimal> shortened;

  /// One figure a day, the balance of the day.
  final bool net;

  /// Colour tells spending from income; [sign] does where colour is lost.
  String format(Decimal amount, {bool? sign}) =>
      (sign == null ? '' : (sign ? '+' : '−')) +
      (shortened.contains(amount)
          ? money.bareCompact(amount)
          : money.bare(amount));

  static const double _maxSize = 10;
  static const double _maxDesktop = 13;
  static const double _minSize = 8;

  static TextStyle _style(double size) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w600,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );
}

/// Weekend columns in `warning`.
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
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: i >= 5 ? sage.warning : sage.inkLabel),
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
    required this.label,
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
  final String label;
  final _Figures figures;
  final VoidCallback onTap;
  final ValueChanged<Offset> onHold;

  Widget _netFigure(DayTotals day, SageColors sage, Color ink) {
    final Decimal net = day.income - day.expenses;
    final bool gain = net > Decimal.zero;
    return _CellFigure(
      text: figures.format(
        net.abs(),
        sign: isToday && net != Decimal.zero ? gain : null,
      ),
      size: figures.size,
      color: isToday
          ? ink
          : net == Decimal.zero
          ? sage.inkLabel
          : gain
          ? sage.accentStrong
          : sage.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DayTotals? day = totals;
    final Color ink = isOutsideMonth && !isToday
        ? sage.inkLabel
        : CellDecoration.inkOf(sage, mark, isToday: isToday);

    return DayCellTap(
      label: label,
      isSelected: isSelected,
      onTap: onTap,
      onHold: onHold,
      child: CellDecoration(
        mark: mark,
        isSelected: isSelected,
        isToday: isToday,
        dimmed: isOutsideMonth,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  date.day.toString(),
                  style: text.labelMedium?.copyWith(
                    fontSize: desktopInput ? 15 : null,
                    color: ink,
                    fontWeight: isSelected || isToday
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
                if (figures.net && day != null && !day.isEmptyMoney)
                  _netFigure(day, sage, ink)
                else if (day != null && day.expenses > Decimal.zero)
                  _CellFigure(
                    text: figures.format(
                      day.expenses,
                      sign: isToday ? false : null,
                    ),
                    size: figures.size,
                    color: isToday ? ink : sage.danger,
                  ),
                if (!figures.net && day != null && day.income > Decimal.zero)
                  _CellFigure(
                    text: figures.format(
                      day.income,
                      sign: isToday ? true : null,
                    ),
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
        ),
      ),
    );
  }
}

extension on DayTotals {
  bool get isEmptyMoney => expenses == Decimal.zero && income == Decimal.zero;
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
