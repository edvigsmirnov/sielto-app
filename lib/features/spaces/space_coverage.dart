import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/space/period_ledger.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Coverage per Space for the switcher. One walk per Space. Uncomputable
/// Spaces are absent.
final FutureProvider<Map<String, Coverage>> spaceCoverageProvider =
    FutureProvider<Map<String, Coverage>>((Ref ref) async {
      final List<Space> spaces =
          ref.watch(spaceListProvider).value ?? const <Space>[];
      final Repositories repos = ref.watch(repositoriesProvider);

      ref.watch(spacePaymentsProvider);
      ref.watch(spaceIncomesProvider);

      final Map<String, Coverage> result = <String, Coverage>{};
      for (final Space space in spaces) {
        final Coverage? coverage = await _coverageOf(repos, space);
        if (coverage != null) result[space.id] = coverage;
      }
      return result;
    });

Future<Coverage?> _coverageOf(Repositories repos, Space space) async {
  final CalendarDate today = repos.spaces.clockFor(space).today();
  final List<Payment> payments = await repos.payments.inSpace(space.id);
  final List<Income> incomes = await repos.incomes.inSpace(space.id);

  if (space.budgetMode != BudgetMode.incomeDriven) {
    return buildFlowLedger(
      space: space,
      payments: payments,
      incomes: incomes,
      today: today,
    ).coverage;
  }

  final List<BudgetPeriod> periods = await repos.periods.incomeDrivenIn(
    space.id,
  );
  final BudgetPeriod? current = periods
      .where(
        (BudgetPeriod p) =>
            !p.startDate.isAfter(today) &&
            (p.endDate == null || !p.endDate!.isBefore(today)),
      )
      .firstOrNull;
  // No period yet: nothing to report.
  if (current == null) return null;

  final List<IncomeRecurrenceRule> rules = await repos.incomeRules.inSpace(
    space.id,
  );
  return buildPeriodLedger(
    period: current,
    payments: payments,
    incomes: incomes,
    anchorRuleIds: <String>{
      for (final IncomeRecurrenceRule r in rules)
        if (r.isAnchor) r.id,
    },
    today: today,
  ).coverage;
}
