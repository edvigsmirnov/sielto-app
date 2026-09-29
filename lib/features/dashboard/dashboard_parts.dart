import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/analytics/analytics_page.dart';
import 'package:sielto/features/shell/shell_tab.dart';

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

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final bool short = amount == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SageRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
        child: Column(
          children: <Widget>[
            Text(
              short && lastCoveredDay != null ? tr('dashboard.lasts') : label,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: sage.inkLabel),
            ),
            const SizedBox(height: SageSpace.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  child: Text(
                    switch ((amount, lastCoveredDay)) {
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

/// Base remainder after mandatory payments, with an explanation toggle.
class CascadeCard extends ConsumerStatefulWidget {
  const CascadeCard({
    required this.available,
    required this.baseRemainder,
    required this.baseCoverage,
    required this.money,
    super.key,
  });

  /// Starting sum; the bar shows the remainder as its share.
  final Decimal available;

  final Decimal? baseRemainder;

  /// Null when the cycle is not judged.
  final Coverage? baseCoverage;

  final MoneyFormat money;

  @override
  ConsumerState<CascadeCard> createState() => _CascadeCardState();
}

class _CascadeCardState extends ConsumerState<CascadeCard> {
  bool _explained = false;

  @override
  Widget build(BuildContext context) {
    // Closes the explanation when the Dashboard tab is left.
    ref.listen<int>(shellTabProvider, (int? _, int tab) {
      if (tab != ShellTabController.dashboard && _explained) {
        setState(() => _explained = false);
      }
    });
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final Decimal? remainder = widget.baseRemainder;

    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(tr('dashboard.cascade'), style: text.titleSmall),
              ),
              _HelpToggle(
                open: _explained,
                onTap: () => setState(() => _explained = !_explained),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: !_explained
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: SageSpace.md),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(SageSpace.md),
                        decoration: BoxDecoration(
                          color: sage.accentTint,
                          borderRadius: BorderRadius.circular(
                            SageRadius.button,
                          ),
                        ),
                        child: Text(
                          tr('dashboard.cascadeHint'),
                          style: text.bodySmall?.copyWith(
                            color: sage.inkSecondary,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: SageSpace.md),
          StatRow(
            label: tr('dashboard.baseRemainder'),
            value: remainder == null
                ? tr('dashboard.notCovered')
                : widget.money.format(remainder),
            valueColor: CoverageDot.colorOf(context, widget.baseCoverage),
            emphasised: true,
          ),
          const SizedBox(height: SageSpace.sm),
          _RemainderBar(
            available: widget.available,
            remainder: remainder,
            coverage: widget.baseCoverage,
          ),
        ],
      ),
    );
  }
}

class _HelpToggle extends StatelessWidget {
  const _HelpToggle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: open ? sage.accentTintAlt : Colors.transparent,
          border: Border.all(color: sage.border),
        ),
        child: Text(
          '?',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: sage.inkLabel),
        ),
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
        StatRow(label: tr('dashboard.planned'), value: money.format(planned)),
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
