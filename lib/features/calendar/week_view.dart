import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_cell.dart';
import 'package:sielto/features/calendar/day_marks.dart';

/// The Week view: seven full-width rows, Monday at the top (spec 8.1).
///
/// Roomier than a Month cell, so each row carries the weekday, the date, the
/// day's figure and — where there is one — the categories it went to. Names
/// only, no amounts per name: the amounts are the Day view's job.
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

  /// The Monday the week starts on.
  final CalendarDate week;

  final CalendarDate selected;
  final Map<CalendarDate, DayTotals> totals;
  final DayMarks marks;

  /// Up to [maxCategoryNames] category titles per day, in spend order.
  final Map<CalendarDate, List<String>> categories;

  final CalendarDate today;
  final MoneyFormat money;
  final DateLabels dates;
  final ValueChanged<CalendarDate> onOpenDay;
  final void Function(CalendarDate date, Offset at) onHoldDay;

  /// What fits on one line under the date (spec 8.1).
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
    final Color ink = CellDecoration.inkOf(sage, mark, isSelected: isSelected);
    final bool isToday = date == today;

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (LongPressStartDetails d) => onHold(d.globalPosition),
      child: CellDecoration(
        mark: mark,
        isSelected: isSelected,
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
                        color: !isSelected && isToday ? sage.accentStrong : ink,
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
                    isSelected: isSelected,
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
                    color: isSelected ? ink : sage.inkLabel,
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

/// The day's figures, or the words for a day with nothing on it.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.totals,
    required this.money,
    required this.isSelected,
    required this.ink,
  });

  final DayTotals? totals;
  final MoneyFormat money;
  final bool isSelected;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DayTotals? day = totals;

    if (day == null || day.isEmpty) {
      return Text(
        tr('calendar.noRecords'),
        style: text.bodyMedium?.copyWith(
          color: isSelected ? ink : sage.inkLabel,
        ),
      );
    }

    final List<Widget> figures = <Widget>[
      if (day.expenses > Decimal.zero)
        Text(
          money.shortSigned(-day.expenses),
          style: text.labelLarge?.copyWith(
            color: isSelected ? ink : sage.danger,
          ),
        ),
      if (day.income > Decimal.zero)
        Text(
          money.shortSigned(day.income),
          style: text.labelLarge?.copyWith(
            color: isSelected ? ink : sage.accentStrong,
          ),
        ),
    ];

    // Only a floating income, so there is a record but no figure (spec 4.7).
    if (figures.isEmpty) {
      return Text(
        tr('income.amountUnknown'),
        style: text.bodyMedium?.copyWith(
          color: isSelected ? ink : sage.inkLabel,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: figures,
    );
  }
}
