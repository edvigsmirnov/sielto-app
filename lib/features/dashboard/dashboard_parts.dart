import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/analytics/analytics_page.dart';
import 'package:sielto/features/dashboard/figure_info.dart';

/// Dashboard blocks shared by the three modes. They take plain values.

/// Hero figure. Shows the remainder while covered, otherwise the day the money
/// runs out, in red.
class MainFigure extends StatelessWidget {
  const MainFigure({
    required this.label,
    required this.amount,
    required this.coverage,
    required this.money,
    required this.overspend,
    required this.lastCoveredDay,
    required this.dates,
    required this.today,
    this.subtitle,
    this.onTap,
    this.info,
    super.key,
  });

  final String label;

  /// Null when not covered or unknown.
  final Decimal? amount;

  final Coverage? coverage;
  final MoneyFormat money;

  /// Final balance; shown as overspend when negative.
  final Decimal overspend;

  final CalendarDate? lastCoveredDay;
  final DateLabels dates;
  final CalendarDate today;

  /// Line under the figure, e.g. Flow's average daily spend.
  final String? subtitle;

  final VoidCallback? onTap;

  final FigureInfo? info;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final bool short = amount == null;
    // An expense due today that the money cannot cover.
    final bool shortToday =
        short && lastCoveredDay != null && lastCoveredDay!.isBefore(today);
    final CalendarDate? shownDay = shortToday ? today : lastCoveredDay;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  child: Text(
                    shortToday
                        ? tr('dashboard.shortFrom')
                        : short && lastCoveredDay != null
                        ? tr('dashboard.lasts')
                        : label,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: sage.inkLabel),
                  ),
                ),
                if (info != null) InfoButton(info!),
              ],
            ),
            const SizedBox(height: SageSpace.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  child: Text(
                    switch ((amount, shownDay)) {
                      (final Decimal value, _) => money.format(value),
                      (null, final CalendarDate day) => dates.dayMonth(
                        day,
                        reference: today,
                      ),
                      (null, null) => money.format(overspend),
                    },
                    textAlign: TextAlign.center,
                    style: text.displaySmall?.copyWith(
                      color: short ? sage.danger : sage.ink,
                    ),
                  ),
                ),
                if (coverage != null) ...<Widget>[
                  const SizedBox(width: SageSpace.sm),
                  CoverageDot(coverage!),
                ],
              ],
            ),
            // Covered, but the money runs out before the end.
            if (!short && lastCoveredDay != null) ...<Widget>[
              const SizedBox(height: SageSpace.xs),
              Text(
                tr(
                  'dashboard.moneyEndsOn',
                  namedArgs: <String, String>{
                    'date': dates.dayMonth(lastCoveredDay!, reference: today),
                  },
                ),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: sage.warningAccent),
              ),
            ],
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: SageSpace.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: sage.inkLabel),
              ),
            ],
            if (short && overspend < Decimal.zero) ...<Widget>[
              const SizedBox(height: SageSpace.xs),
              Text(
                tr(
                  'dashboard.overspend',
                  namedArgs: <String, String>{
                    'amount': money.format(-overspend),
                  },
                ),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: sage.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Spent total, for a cycle without a fund or income.
class SpentFigure extends StatelessWidget {
  const SpentFigure({required this.amount, required this.money, super.key});

  final Decimal amount;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
      child: Column(
        children: <Widget>[
          Text(
            tr('budget.spent'),
            style: text.bodyMedium?.copyWith(color: context.sage.inkLabel),
          ),
          const SizedBox(height: SageSpace.xs),
          Text(money.format(amount), style: text.displaySmall),
        ],
      ),
    );
  }
}

/// What is left after the mandatory payments alone.
class CascadeCard extends StatelessWidget {
  const CascadeCard({
    required this.available,
    required this.baseRemainder,
    required this.baseCoverage,
    required this.money,
    this.info,
    super.key,
  });

  /// Starting sum; the bar shows the remainder as its share.
  final Decimal available;

  final Decimal? baseRemainder;

  /// Null when the cycle is not judged.
  final Coverage? baseCoverage;

  final MoneyFormat money;

  final FigureInfo? info;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Decimal? remainder = baseRemainder;

    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(tr('dashboard.afterBills'), style: text.titleSmall),
              ),
              if (info != null) InfoButton(info!),
            ],
          ),
          const SizedBox(height: SageSpace.sm),
          StatRow(
            label: tr('dashboard.afterBillsLeft'),
            value: remainder == null
                ? tr('dashboard.notCovered')
                : money.format(remainder),
            valueColor: CoverageDot.colorOf(context, baseCoverage),
            emphasised: true,
          ),
          const SizedBox(height: SageSpace.sm),
          _RemainderBar(
            available: available,
            remainder: remainder,
            coverage: baseCoverage,
          ),
        ],
      ),
    );
  }
}

/// Share of the money left after mandatory payments.
class _RemainderBar extends StatelessWidget {
  const _RemainderBar({
    required this.available,
    required this.remainder,
    required this.coverage,
  });

  final Decimal available;
  final Decimal? remainder;
  final Coverage? coverage;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    // Empty when nothing is left or nothing was available.
    final double share = (remainder == null || available <= Decimal.zero)
        ? 0
        : (remainder!.toDouble() / available.toDouble()).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(SageRadius.pill),
      child: LinearProgressIndicator(
        value: share,
        minHeight: 6,
        backgroundColor: sage.accentTintAlt,
        valueColor: AlwaysStoppedAnimation<Color>(
          CoverageDot.colorOf(context, coverage),
        ),
      ),
    );
  }
}

/// Planned, paid, still to pay.
class TotalsCard extends StatelessWidget {
  const TotalsCard({
    required this.planned,
    required this.paid,
    required this.remaining,
    required this.money,
    super.key,
  });

  final Decimal planned;
  final Decimal paid;
  final Decimal remaining;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context) => SageCard(
    child: Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: StatRow(
                label: tr('dashboard.planned'),
                value: money.format(planned),
              ),
            ),
            InfoButton(
              FigureInfo(
                title: tr('dashboard.planned'),
                what: tr('info.totals'),
                sum: <SumLine>[
                  SumLine('', money.format(planned), tr('info.planned')),
                  SumLine('−', money.format(paid), tr('info.paid')),
                  SumLine('=', money.format(remaining), tr('info.toPay')),
                ],
              ),
            ),
          ],
        ),
        StatRow(label: tr('dashboard.paid'), value: money.format(paid)),
        StatRow(
          label: tr('dashboard.leftToPay'),
          value: money.format(remaining),
        ),
      ],
    ),
  );
}

/// "In 5 days — Salary: 2 400 €", on the accent tint.
class NearestIncomeCard extends StatelessWidget {
  const NearestIncomeCard({
    required this.income,
    required this.today,
    required this.money,
    this.onTap,
    super.key,
  });

  final Income? income;
  final CalendarDate today;
  final MoneyFormat money;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final Income? row = income;

    if (row == null) {
      return SageCard(
        child: Text(tr('dashboard.noUpcomingIncome'), style: text.bodyMedium),
      );
    }

    final int days = today.daysUntil(row.expectedDate);
    final Decimal? amount = row.amount;

    return SageCard(
      color: sage.accentTint,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(tr('dashboard.nearestIncome'), style: text.titleSmall),
          const SizedBox(height: SageSpace.xs),
          Text(
            days == 0
                ? tr('dashboard.incomeToday')
                : plural('dashboard.incomeInDays', days),
            style: text.bodySmall?.copyWith(color: sage.inkSecondary),
          ),
          const SizedBox(height: SageSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  row.title,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: SageSpace.md),
              Text(
                amount == null
                    ? tr('income.amountUnknown')
                    : '+${money.format(amount)}',
                style: text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: amount == null ? sage.inkLabel : sage.accentStrong,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Space's mode.
class ModeBadge extends StatelessWidget {
  const ModeBadge(this.mode, {super.key});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SageSpace.md,
          vertical: SageSpace.xs,
        ),
        decoration: BoxDecoration(
          color: sage.accentTintAlt,
          borderRadius: BorderRadius.circular(SageRadius.pill),
        ),
        child: Text(
          mode,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: sage.accentStrong),
        ),
      ),
    );
  }
}

/// Link to Analytics at the foot of the Dashboard.
class AnalyticsLink extends StatelessWidget {
  const AnalyticsLink({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => AnalyticsPage.open(context),
      child: Text(
        '${tr('analytics.open')} \u2192',
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: context.sage.accentStrong),
      ),
    ),
  );
}
