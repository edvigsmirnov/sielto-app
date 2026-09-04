import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// The Year view: twelve cards, three figures each (spec 8.1).
///
/// In, out, and the difference — the only view that shows a net, because a
/// month is the shortest span over which "did it balance" is a real question.
/// Tapping one opens that month.
class YearView extends StatelessWidget {
  const YearView({
    required this.year,
    required this.totals,
    required this.today,
    required this.selected,
    required this.money,
    required this.dates,
    required this.onOpenMonth,
    super.key,
  });

  final int year;

  /// Keyed by the first of each month.
  final Map<CalendarDate, DayTotals> totals;

  final CalendarDate today;
  final CalendarDate selected;
  final MoneyFormat money;
  final DateLabels dates;
  final ValueChanged<CalendarDate> onOpenMonth;

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 3,
    childAspectRatio: 0.82,
    mainAxisSpacing: SageSpace.sm,
    crossAxisSpacing: SageSpace.sm,
    padding: const EdgeInsets.only(bottom: SageSpace.lg),
    children: <Widget>[
      for (int month = 1; month <= 12; month++)
        _MonthCard(
          month: CalendarDate(year, month, 1),
          totals: totals[CalendarDate(year, month, 1)],
          isCurrent: today.year == year && today.month == month,
          isSelected: selected.year == year && selected.month == month,
          money: money,
          dates: dates,
          onTap: () => onOpenMonth(CalendarDate(year, month, 1)),
        ),
    ],
  );
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.totals,
    required this.isCurrent,
    required this.isSelected,
    required this.money,
    required this.dates,
    required this.onTap,
  });

  final CalendarDate month;
  final DayTotals? totals;
  final bool isCurrent;
  final bool isSelected;
  final MoneyFormat money;
  final DateLabels dates;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final DayTotals? sums = totals;
    final bool empty = sums == null || sums.isEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.card),
      child: Opacity(
        // A month with nothing in it is still a month: present, and clearly
        // not carrying an answer.
        opacity: empty ? 0.45 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected ? sage.accentTint : sage.card,
            borderRadius: BorderRadius.circular(SageRadius.card),
            border: Border.all(
              color: isSelected ? sage.accentStrong : sage.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(SageSpace.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  dates.monthShort(month),
                  maxLines: 1,
                  style: text.labelLarge?.copyWith(
                    color: isCurrent ? sage.accentStrong : sage.inkHeading,
                  ),
                ),
                const SizedBox(height: SageSpace.xs),
                if (empty)
                  Text('—', style: text.bodyMedium)
                else ...<Widget>[
                  _Line(
                    text: '↑${money.short(sums.income)}',
                    color: sage.accentStrong,
                  ),
                  _Line(
                    text: '↓${money.short(sums.expenses)}',
                    color: sage.danger,
                  ),
                  const SizedBox(height: 2),
                  _Line(
                    text: money.shortSigned(sums.net),
                    color: sums.net < Decimal.zero
                        ? sage.danger
                        : sage.accentStrong,
                    emphasised: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One figure on a month card. Tabular, so the three lines and the twelve
/// cards all align.
class _Line extends StatelessWidget {
  const _Line({
    required this.text,
    required this.color,
    this.emphasised = false,
  });

  final String text;
  final Color color;

  /// The net, which is the figure the card is about.
  final bool emphasised;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.clip,
    style: TextStyle(
      fontSize: emphasised ? 13 : 11,
      fontWeight: emphasised ? FontWeight.w700 : FontWeight.w600,
      color: color,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    ),
  );
}
