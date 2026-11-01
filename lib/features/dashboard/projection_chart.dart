import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/format/context_format.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/ledger/daily_projection.dart';
import 'package:sielto/features/dashboard/figure_info.dart';

/// Next ten days as columns.
class ProjectionCard extends StatelessWidget {
  const ProjectionCard({
    required this.projection,
    required this.money,
    super.key,
  });

  final DailyProjection projection;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final DateLabels dates = context.dates;

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
            child: _Columns(projection: projection, money: money, dates: dates),
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
  const _Columns({
    required this.projection,
    required this.money,
    required this.dates,
  });

  final DailyProjection projection;
  final MoneyFormat money;
  final DateLabels dates;

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
            child: Semantics(
              label:
                  '${dates.dayMonth(projection.days[i])}: '
                  '${money.format(projection.balances[i])}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _Column(
                  fraction: span == 0
                      ? 0
                      : (projection.balances[i] - bottom).toDouble() / span,
                  isNegative: projection.balances[i] < Decimal.zero,
                  isToday: i == 0,
                  sage: sage,
                ),
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
