import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/ledger/ledger_entry.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/dashboard/figure_info.dart';

/// End-of-day balances for the next few days.
@immutable
class DailyProjection {
  const DailyProjection({
    required this.days,
    required this.balances,
    required this.spend,
    required this.averageSpendPerDay,
  });

  static const int horizonDays = 10;

  final List<CalendarDate> days;

  final List<Decimal> balances;

  /// Planned spend over the window.
  final Decimal spend;

  /// [spend] divided by the window's length. Zero when nothing is
  /// planned.
  final Decimal averageSpendPerDay;

  bool get isEmpty => days.isEmpty;

  Decimal get lowest => balances.isEmpty
      ? Decimal.zero
      : balances.reduce((Decimal a, Decimal b) => a < b ? a : b);

  Decimal get highest => balances.isEmpty
      ? Decimal.zero
      : balances.reduce((Decimal a, Decimal b) => a > b ? a : b);
}

/// Day-by-day walk over the window; entries land on their own dates.
DailyProjection projectDays({
  required Decimal available,
  required List<LedgerEntry> entries,
  required CalendarDate from,
  int horizon = DailyProjection.horizonDays,
}) {
  final List<CalendarDate> days = <CalendarDate>[
    for (int i = 0; i < horizon; i++) from.addDays(i),
  ];
  final CalendarDate last = days.last;

  // Entries before the window are in the opening balance.
  Decimal balance = available;
  for (final LedgerEntry e in entries) {
    if (!e.date.isBefore(from)) continue;
    balance = e.isIncome ? balance + e.amount : balance - e.amount;
  }

  Decimal spend = Decimal.zero;
  final List<Decimal> balances = <Decimal>[];
  for (final CalendarDate day in days) {
    for (final LedgerEntry e in entries) {
      if (e.date != day) continue;
      if (e.isIncome) {
        balance += e.amount;
      } else {
        balance -= e.amount;
        if (!e.date.isAfter(last)) spend += e.amount;
      }
    }
    balances.add(balance);
  }

  return DailyProjection(
    days: days,
    balances: balances,
    spend: spend,
    averageSpendPerDay: (spend / Decimal.fromInt(horizon)).toDecimal(
      scaleOnInfinitePrecision: 2,
    ),
  );
}

/// Next ten days as columns.
class ProjectionCard extends StatelessWidget {
  const ProjectionCard({
    required this.projection,
    required this.money,
    required this.dates,
    required this.today,
    super.key,
  });

  final DailyProjection projection;
  final MoneyFormat money;
  final DateLabels dates;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    if (projection.isEmpty) return const SizedBox.shrink();

    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                plural('dashboard.projection', DailyProjection.horizonDays),
                style: text.titleSmall,
              ),
              InfoButton(
                FigureInfo(
                  title: plural(
                    'dashboard.projection',
                    DailyProjection.horizonDays,
                  ),
                  what: tr('info.projection'),
                  note: tr('info.projectionNote'),
                ),
              ),
            ],
          ),
          const SizedBox(height: SageSpace.md),
          SizedBox(
            height: 72,
            child: _Columns(projection: projection, today: today),
          ),
          const SizedBox(height: SageSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                dates.dayMonth(projection.days.first),
                style: text.bodySmall,
              ),
              Text(dates.dayMonth(projection.days.last), style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _Columns extends StatelessWidget {
  const _Columns({required this.projection, required this.today});

  final DailyProjection projection;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final Decimal highest = projection.highest;
    final Decimal lowest = projection.lowest;

    // The scale includes zero so negative columns go below the line.
    final Decimal top = highest > Decimal.zero ? highest : Decimal.zero;
    final Decimal bottom = lowest < Decimal.zero ? lowest : Decimal.zero;
    final double span = (top - bottom).toDouble();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int i = 0; i < projection.days.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _Column(
                fraction: span == 0
                    ? 0
                    : (projection.balances[i] - bottom).toDouble() / span,
                isNegative: projection.balances[i] < Decimal.zero,
                isToday: projection.days[i] == today,
                sage: sage,
              ),
            ),
          ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.fraction,
    required this.isNegative,
    required this.isToday,
    required this.sage,
  });

  final double fraction;
  final bool isNegative;
  final bool isToday;
  final SageColors sage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double height = (constraints.maxHeight * fraction).clamp(
        3,
        constraints.maxHeight,
      );
      return Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          height: height,
          decoration: BoxDecoration(
            color: isNegative
                ? sage.danger
                : (isToday ? sage.accentStrong : sage.accent),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
    },
  );
}
