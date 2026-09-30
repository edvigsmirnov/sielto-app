import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/dashboard/dashboard_parts.dart';
import 'package:sielto/features/dashboard/period_selector.dart';
import 'package:sielto/features/incomes/anchor_help.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/incomes/income_rules_page.dart';
import 'package:sielto/features/overdue/overdue.dart';
import 'package:sielto/features/periods/freeze_ui.dart';
import 'package:sielto/features/space/period_ledger.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Regular-income Space dashboard: no anchor yet, anchor without an amount, or
/// the period figures.
class PeriodDashboardBody extends ConsumerWidget {
  const PeriodDashboardBody({required this.space, super.key});

  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<IncomeRecurrenceRule> rules =
        ref.watch(incomeRulesProvider).value ?? const <IncomeRecurrenceRule>[];
    final bool hasAnchor = rules.any((IncomeRecurrenceRule r) => r.isAnchor);

    if (!hasAnchor) return const _NoAnchorState();

    final AsyncValue<PeriodLedger> ledger = ref.watch(periodLedgerProvider);
    return ledger.when(
      loading: () => const Center(child: LeafLoader()),
      error: (Object e, StackTrace _) =>
          EmptyState(message: tr('common.loadFailed')),
      data: (PeriodLedger data) => _PeriodBody(space: space, ledger: data),
    );
  }
}

/// No regular income yet. The Feed and Calendar still work.
class _NoAnchorState extends StatelessWidget {
  const _NoAnchorState();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SageSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.savings_outlined,
              size: 40,
              color: context.sage.inkLabel,
            ),
            const SizedBox(height: SageSpace.lg),
            Text(
              tr('period.noAnchorTitle'),
              textAlign: TextAlign.center,
              style: text.titleSmall,
            ),
            const SizedBox(height: SageSpace.sm),
            Text(
              tr('period.noAnchorBody'),
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: SageSpace.lg),
            FilledButton(
              onPressed: () => openIncomeForm(context),
              child: Text(tr('income.add')),
            ),
            TextButton(
              onPressed: () => showAnchorHelp(context),
              child: Text(tr('income.anchorHelpTitle')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodBody extends ConsumerWidget {
  const _PeriodBody({required this.space, required this.ledger});

  final Space space;
  final PeriodLedger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String locale = context.locale.toString();
    final MoneyFormat money = MoneyFormat(
      locale: locale,
      currencyCode: space.currencyCode,
    );
    final DateLabels dates = DateLabels(locale);

    final bool atBottom = ref
        .watch(controlsAtBottomProvider)
        .contains(ControlsScreen.dashboard);

    final Widget list = ListView(
      padding: const EdgeInsets.all(SageSpace.gutter),
      children: <Widget>[
        if (!atBottom) ...<Widget>[
          const PeriodSelector(),
          const SizedBox(height: SageSpace.sm),
        ],
        FreezeBanner(period: ledger.period),
        if (!ledger.isComputable)
          _FloatingAnchorCard(ledger: ledger, money: money)
        // No income in the cycle: show the spent total.
        else if (!ledger.hasIncome)
          SpentFigure(amount: ledger.totalPaid, money: money)
        else ...<Widget>[
          MainFigure(
            label: tr('dashboard.freeMoney'),
            amount: ledger.freeCash,
            coverage: ledger.coverage,
            money: money,
            overspend: ledger.cascade!.all.finalBalance,
            lastCoveredDay: ledger.lastCoveredDay,
            dates: dates,
            today: ledger.today,
          ),
          const SizedBox(height: SageSpace.md),
          CascadeCard(
            available: ledger.anchorAmount!,
            baseRemainder: ledger.baseRemainder,
            baseCoverage: ledger.baseCoverage,
            money: money,
          ),
        ],
        const SizedBox(height: SageSpace.md),
        OverdueChip(
          money: money,
          margin: const EdgeInsets.only(bottom: SageSpace.md),
        ),
        TotalsCard(
          planned: ledger.totalPlanned,
          paid: ledger.totalPaid,
          remaining: ledger.totalRemaining,
          money: money,
        ),
        const SizedBox(height: SageSpace.md),
        NearestIncomeCard(
          income: ledger.nearestIncome,
          today: ledger.today,
          money: money,
          onTap: ledger.nearestIncome == null
              ? null
              : () =>
                    openIncomeForm(context, incomeId: ledger.nearestIncome!.id),
        ),
        const SizedBox(height: SageSpace.md),
        SageCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => const IncomeRulesPage(),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.repeat, size: 20, color: context.sage.inkLabel),
              const SizedBox(width: SageSpace.md),
              Expanded(
                child: Text(
                  tr('income.regularTitle'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.sage.inkLabel),
            ],
          ),
        ),
        const AnalyticsLink(),
      ],
    );
    if (!atBottom) return list;
    return Column(
      children: <Widget>[
        Expanded(child: list),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: SageSpace.gutter),
          child: PeriodSelector(swipe: false),
        ),
      ],
    );
  }
}

/// Anchor income without an amount: expenses shown, remainder not computed.
class _FloatingAnchorCard extends StatelessWidget {
  const _FloatingAnchorCard({required this.ledger, required this.money});

  final PeriodLedger ledger;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Income? income = ledger.nearestIncome;

    return SageCard(
      padding: const EdgeInsets.all(SageSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(tr('period.amountUnknownTitle'), style: text.titleSmall),
          const SizedBox(height: SageSpace.sm),
          Text(tr('period.amountUnknownBody'), style: text.bodySmall),
          const SizedBox(height: SageSpace.md),
          const Hairline(),
          const SizedBox(height: SageSpace.md),
          Row(
            children: <Widget>[
              Expanded(
                child: StatColumn(
                  label: tr('dashboard.planned'),
                  value: money.format(ledger.totalPlanned),
                ),
              ),
              TextButton(
                onPressed: () => openIncomeForm(
                  context,
                  incomeId: income?.id,
                  date: income == null ? ledger.period.startDate : null,
                ),
                child: Text(tr('period.setAmount')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
