import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/dashboard/balance_sheet.dart';
import 'package:sielto/features/dashboard/dashboard_parts.dart';
import 'package:sielto/features/dashboard/figure_info.dart';
import 'package:sielto/features/dashboard/projection_chart.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/overdue/overdue.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Flow Space dashboard: how far the money reaches, and a 10-day projection.
class FlowDashboardBody extends ConsumerWidget {
  const FlowDashboardBody({required this.space, super.key});

  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FlowLedger> ledger = ref.watch(flowLedgerProvider);
    return ledger.when(
      loading: () => const Center(child: LeafLoader()),
      error: (Object e, StackTrace _) =>
          EmptyState(message: tr('common.loadFailed')),
      data: (FlowLedger data) => _Body(space: space, ledger: data),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.space, required this.ledger});

  final Space space;
  final FlowLedger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String locale = context.locale.toString();
    final MoneyFormat money = MoneyFormat(
      locale: locale,
      currencyCode: space.currencyCode,
    );
    final DateLabels dates = DateLabels(locale);
    final DailyProjection projection = projectDays(
      available: ledger.available,
      entries: ledger.entries,
      from: ledger.today,
    );

    return ListView(
      padding: const EdgeInsets.all(SageSpace.gutter),
      children: <Widget>[
        MainFigure(
          label: tr('dashboard.freeMoney'),
          amount: ledger.freeCash,
          coverage: ledger.coverage,
          money: money,
          overspend: ledger.cascade.all.finalBalance,
          lastCoveredDay: ledger.lastCoveredDay,
          dates: dates,
          today: ledger.today,
          subtitle: tr(
            'dashboard.atAverageSpend',
            namedArgs: <String, String>{
              'amount': money.format(projection.averageSpendPerDay),
            },
          ),
          onTap: () =>
              showBalanceSheet(context, ref, space: space, money: money),
          info: moneyLeftInfo(
            title: tr('dashboard.freeMoney'),
            what: tr('info.leftFlow'),
            run: ledger.cascade.all,
            money: money,
            dates: dates,
            today: ledger.today,
            startLabel: tr('info.now'),
          ),
        ),
        const SizedBox(height: SageSpace.md),
        OverdueChip(
          money: money,
          margin: const EdgeInsets.only(bottom: SageSpace.md),
        ),
        ProjectionCard(
          projection: projection,
          money: money,
          dates: dates,
          today: ledger.today,
        ),
        const SizedBox(height: SageSpace.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _FigureTile(
                value: money.format(ledger.available),
                label: tr('dashboard.currentMoney'),
                // When the balance was set, so a stale one shows as stale.
                caption: _balanceCaption(space, ledger, dates),
                // Tapping the balance edits it.
                onTap: () =>
                    showBalanceSheet(context, ref, space: space, money: money),
                info: FigureInfo(
                  title: tr('dashboard.currentMoney'),
                  what: tr('info.balance'),
                  note: ledger.excludedCount > 0
                      ? tr('info.balanceNote')
                      : null,
                ),
              ),
            ),
            const SizedBox(width: SageSpace.sm),
            Expanded(
              child: _FigureTile(
                value: money.format(projection.averageSpendPerDay),
                label: tr('dashboard.perDay'),
                info: FigureInfo(
                  title: tr('dashboard.perDay'),
                  what: tr('info.perDay'),
                  sum: <SumLine>[
                    SumLine(
                      '',
                      money.format(projection.spend),
                      plural('info.plannedFor', DailyProjection.horizonDays),
                    ),
                    SumLine(
                      '÷',
                      '${DailyProjection.horizonDays}',
                      tr('info.days'),
                    ),
                    SumLine(
                      '=',
                      money.format(projection.averageSpendPerDay),
                      tr('info.aDay'),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
        TotalsCard(
          planned: ledger.totalPlanned,
          paid: ledger.totalPaid,
          remaining: ledger.totalRemaining,
          money: money,
        ),
        const AnalyticsLink(),
      ],
    );
  }
}

/// When the balance was set, and how many records the walk excluded.
String? _balanceCaption(Space space, FlowLedger ledger, DateLabels dates) {
  final CalendarDate? setOn = space.balanceSetOn;
  return <String>[
    if (setOn != null)
      tr(
        'dashboard.balanceSetOn',
        namedArgs: <String, String>{'date': dates.short(setOn)},
      ),
    if (ledger.excludedCount > 0)
      plural('balance.excludedFromWalker', ledger.excludedCount),
  ].join(' · ').ifEmptyNull();
}

extension on String {
  String? ifEmptyNull() => isEmpty ? null : this;
}

/// Amount over label.
class _FigureTile extends StatelessWidget {
  const _FigureTile({
    required this.value,
    required this.label,
    this.caption,
    this.onTap,
    this.info,
  });

  final String value;
  final String label;

  final FigureInfo? info;

  /// Qualifies the figure.
  final String? caption;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SageCard(
      padding: const EdgeInsets.symmetric(
        horizontal: SageSpace.sm,
        vertical: SageSpace.md,
      ),
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: context.sage.inkLabel),
                ),
              ),
              if (info != null) InfoButton(info!),
            ],
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: text.labelSmall?.copyWith(color: context.sage.inkLabel),
            ),
        ],
      ),
    );
  }
}
