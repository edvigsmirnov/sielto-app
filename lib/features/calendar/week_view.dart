import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_cell.dart';
import 'package:sielto/features/calendar/day_marks.dart';

/// Seven rows, Monday first: date, figures and top categories.
class WeekView extends StatelessWidget {
  const WeekView({
    required this.week,
    required this.selected,
    required this.totals,
    required this.marks,
    required this.categories,
    required this.today,
    required this.money,
    required this.dates,
    required this.onOpenDay,
    required this.onHoldDay,
    super.key,
  });

  /// Always a Monday.
  final CalendarDate week;

  final CalendarDate selected;
  final Map<CalendarDate, DayTotals> totals;
  final DayMarks marks;

  /// Up to [maxCategoryNames] titles per day, in spend order.
  final Map<CalendarDate, List<String>> categories;

  final CalendarDate today;
  final MoneyFormat money;
  final DateLabels dates;
  final ValueChanged<CalendarDate> onOpenDay;
  final void Function(CalendarDate date, Offset at) onHoldDay;

  static const int maxCategoryNames = 3;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.only(bottom: SageSpace.lg),
    itemCount: 7,
    separatorBuilder: (BuildContext _, int _) =>
        const SizedBox(height: SageSpace.sm),
    itemBuilder: (BuildContext context, int index) {
      final CalendarDate date = week.addDays(index);
      return _WeekRow(
        date: date,
        totals: totals[date],
        mark: marks[date],
        categories: categories[date] ?? const <String>[],
        isSelected: date == selected,
        today: today,
        money: money,
        dates: dates,
        onTap: () => onOpenDay(date),
        onHold: (Offset at) => onHoldDay(date, at),
      );
    },
  );
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.date,
    required this.totals,
    required this.mark,
    required this.categories,
    required this.isSelected,
    required this.today,
    required this.money,
    required this.dates,
    required this.onTap,
    required this.onHold,
  });

  final CalendarDate date;
  final DayTotals? totals;
  final DayMark mark;
  final List<String> categories;
  final bool isSelected;
  final CalendarDate today;
  final MoneyFormat money;
  final DateLabels dates;
  final VoidCallback onTap;
  final ValueChanged<Offset> onHold;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DayTotals? day = totals;
    final bool isToday = date == today;
    final Color ink = CellDecoration.inkOf(sage, mark, isToday: isToday);

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (LongPressStartDetails d) {
        HapticFeedback.mediumImpact();
        onHold(d.globalPosition);
      },
      child: CellDecoration(
        mark: mark,
        isSelected: isSelected,
        isToday: isToday,
        radius: SageRadius.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SageSpace.md,
            vertical: SageSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${dates.weekdayShort(date)}, '
                      '${dates.dayMonth(date, reference: today)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        color: ink,
                        fontWeight: isSelected || isToday
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: SageSpace.sm),
                  _Figures(
                    totals: day,
                    money: money,
                    isToday: isToday,
                    ink: ink,
                  ),
                ],
              ),
              if (categories.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  categories.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: isToday ? ink : sage.inkLabel,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({
    required this.totals,
    required this.money,
    required this.isToday,
    required this.ink,
  });

  final DayTotals? totals;
  final MoneyFormat money;
  final bool isToday;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DayTotals? day = totals;

    if (day == null || day.isEmpty) {
      return Text(
        tr('calendar.noRecords'),
        style: text.bodyMedium?.copyWith(color: isToday ? ink : sage.inkLabel),
      );
    }

    final List<Widget> figures = <Widget>[
      if (day.expenses > Decimal.zero)
        Text(
          money.shortSigned(-day.expenses),
          style: text.labelLarge?.copyWith(color: isToday ? ink : sage.danger),
        ),
      if (day.income > Decimal.zero)
        Text(
          money.shortSigned(day.income),
          style: text.labelLarge?.copyWith(
            color: isToday ? ink : sage.accentStrong,
          ),
        ),
    ];

    // Only an income without amount.
    if (figures.isEmpty) {
      return Text(
        tr('income.amountUnknown'),
        style: text.bodyMedium?.copyWith(color: isToday ? ink : sage.inkLabel),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: figures,
    );
  }
}
