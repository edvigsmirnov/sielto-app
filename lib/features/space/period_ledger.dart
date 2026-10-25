import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/ledger/ledger_entry.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// One income cycle, walked from its anchor income. `is_paid` changes no
/// figure.
class PeriodLedger extends SpaceLedger {
  const PeriodLedger({
    required this.period,
    required this.anchorAmount,
    required super.cascade,
    required super.entries,
    required super.today,
    required super.totalPlanned,
    required super.totalPaid,
    required this.nearestIncome,
    required this.unknownIncomeCount,
    required this.hasIncome,
    required this.hasUnpaidExpense,
  });

  final BudgetPeriod period;

  /// Null when the anchor income has no amount.
  final Decimal? anchorAmount;

  /// Next income not yet arrived, from today or the period start, in any later
  /// period.
  final Income? nearestIncome;

  /// Incomes in the period without an amount.
  final int unknownIncomeCount;

  final bool hasIncome;

  final bool hasUnpaidExpense;

  @override
  Decimal? get available => anchorAmount;

  bool get isComputable => cascade != null;

  /// A cycle without income and without anything owed is not judged.
  @override
  bool get isJudged => hasIncome || hasUnpaidExpense;
}

PeriodLedger buildPeriodLedger({
  required BudgetPeriod period,
  required List<Payment> payments,
  required List<Income> incomes,
  required Set<String> anchorRuleIds,
  required CalendarDate today,
}) {
  bool isAnchor(Income i) =>
      i.recurrenceRuleId != null && anchorRuleIds.contains(i.recurrenceRuleId);

  // Bound to this period, or unbound and dated inside it.
  final CalendarDate? end = period.endDate;
  bool inPeriod(String? boundTo, CalendarDate date) {
    if (boundTo != null) return boundTo == period.id;
    return !period.startDate.isAfter(date) &&
        (end == null || !end.isBefore(date));
  }

  final List<Payment> ofPeriod = payments
      .where((Payment p) => inPeriod(p.budgetPeriodId, p.dueDate))
      .toList();

  // Anchor incomes count only when bound to this period.
  final List<Income> inflows = incomes
      .where(
        (Income i) => isAnchor(i)
            ? i.budgetPeriodId == period.id
            : inPeriod(i.budgetPeriodId, i.expectedDate),
      )
      .toList();

  // Merged anchors add. No anchor income is zero; an anchor without amount
  // makes the cycle uncomputable.
  Decimal anchorTotal = Decimal.zero;
  bool anchorKnown = false;
  bool anchorUnknown = false;
  for (final Income i in inflows.where(isAnchor)) {
    final Decimal? amount = i.amount;
    if (amount == null) {
      anchorUnknown = true;
      continue;
    }
    anchorTotal += amount;
    anchorKnown = true;
  }
  final Decimal? anchorAmount = (anchorUnknown && !anchorKnown)
      ? null
      : anchorTotal;

  int unknown = 0;
  final List<LedgerEntry> entries = <LedgerEntry>[
    for (final Payment p in ofPeriod) paymentEntry(p),
  ];
  for (final Income i in inflows) {
    if (isAnchor(i)) continue;
    final LedgerEntry? entry = incomeEntry(i);
    if (entry == null) {
      unknown++;
      continue;
    }
    entries.add(entry);
  }

  Decimal planned = Decimal.zero;
  Decimal paid = Decimal.zero;
  for (final Payment p in ofPeriod) {
    planned += p.amount;
    if (p.isPaid) paid += p.amount;
  }

  final CalendarDate from = period.startDate.isAfter(today)
      ? period.startDate
      : today;
  Income? nearest;
  for (final Income i in incomes) {
    if (i.isPaid || i.expectedDate.isBefore(from)) continue;
    if (nearest == null || i.expectedDate.isBefore(nearest.expectedDate)) {
      nearest = i;
    }
  }

  return PeriodLedger(
    period: period,
    anchorAmount: anchorAmount,
    cascade: anchorAmount == null
        ? null
        : LedgerWalker.cascade(available: anchorAmount, entries: entries),
    entries: entries,
    today: today,
    totalPlanned: planned,
    totalPaid: paid,
    nearestIncome: nearest,
    unknownIncomeCount: unknown + (anchorUnknown && anchorKnown ? 1 : 0),
    hasIncome: inflows.isNotEmpty,
    hasUnpaidExpense: ofPeriod.any((Payment p) => !p.isPaid),
  );
}

/// Period shown on Dashboard, Feed and Calendar.
class SelectedPeriodController extends Notifier<String?> {
  @override
  String? build() {
    // Resets when another Space opens, not when this one's row changes.
    ref.watch(currentSpaceIdProvider);
    return null;
  }

  void select(String? periodId) => state = periodId;
}

final NotifierProvider<SelectedPeriodController, String?>
selectedPeriodIdProvider = NotifierProvider<SelectedPeriodController, String?>(
  SelectedPeriodController.new,
);

/// Oldest first.
final Provider<List<BudgetPeriod>> incomePeriodsProvider =
    Provider<List<BudgetPeriod>>((Ref ref) {
      final List<BudgetPeriod> all =
          ref.watch(spacePeriodsProvider).value ?? const <BudgetPeriod>[];
      return all
          .where((BudgetPeriod p) => p.periodType == PeriodType.incomeDriven)
          .toList();
    });

/// Defaults to the period containing today.
final Provider<BudgetPeriod?> selectedPeriodProvider = Provider<BudgetPeriod?>((
  Ref ref,
) {
  final List<BudgetPeriod> periods = ref.watch(incomePeriodsProvider);
  if (periods.isEmpty) return null;

  final String? chosen = ref.watch(selectedPeriodIdProvider);
  for (final BudgetPeriod p in periods) {
    if (p.id == chosen) return p;
  }

  final CalendarDate today = ref.watch(spaceClockProvider).today();
  for (final BudgetPeriod p in periods) {
    if (p.startDate.isAfter(today)) continue;
    final CalendarDate? end = p.endDate;
    if (end == null || !end.isBefore(today)) return p;
  }
  return periods.first;
});

/// Every cycle's figures, oldest first. Independent of the selection.
final Provider<AsyncValue<List<PeriodLedger>>> periodLedgersProvider =
    Provider<AsyncValue<List<PeriodLedger>>>((Ref ref) {
      ref.watch(periodRefreshProvider);

      final AsyncValue<List<Payment>> payments = ref.watch(
        spacePaymentsProvider,
      );
      final AsyncValue<List<Income>> incomes = ref.watch(spaceIncomesProvider);
      final AsyncValue<List<IncomeRecurrenceRule>> rules = ref.watch(
        incomeRulesProvider,
      );

      final Object? error = payments.error ?? incomes.error ?? rules.error;
      if (error != null) {
        return AsyncValue<List<PeriodLedger>>.error(error, StackTrace.current);
      }

      final List<Payment>? paymentRows = payments.value;
      final List<Income>? incomeRows = incomes.value;
      final List<IncomeRecurrenceRule>? ruleRows = rules.value;
      if (paymentRows == null || incomeRows == null || ruleRows == null) {
        return const AsyncValue<List<PeriodLedger>>.loading();
      }

      final Set<String> anchors = <String>{
        for (final IncomeRecurrenceRule r in ruleRows)
          if (r.isAnchor) r.id,
      };
      final CalendarDate today = ref.watch(spaceClockProvider).today();

      return AsyncValue<List<PeriodLedger>>.data(<PeriodLedger>[
        for (final BudgetPeriod period in ref.watch(incomePeriodsProvider))
          buildPeriodLedger(
            period: period,
            payments: paymentRows,
            incomes: incomeRows,
            anchorRuleIds: anchors,
            today: today,
          ),
      ]);
    });

final Provider<AsyncValue<PeriodLedger>> periodLedgerProvider =
    Provider<AsyncValue<PeriodLedger>>((Ref ref) {
      // Watched first: it triggers the refresh that creates the first period.
      final AsyncValue<List<PeriodLedger>> all = ref.watch(
        periodLedgersProvider,
      );
      final BudgetPeriod? period = ref.watch(selectedPeriodProvider);
      if (period == null) return const AsyncValue<PeriodLedger>.loading();

      final Object? error = all.error;
      if (error != null) {
        return AsyncValue<PeriodLedger>.error(error, StackTrace.current);
      }
      final List<PeriodLedger>? ledgers = all.value;
      if (ledgers == null) return const AsyncValue<PeriodLedger>.loading();

      for (final PeriodLedger ledger in ledgers) {
        if (ledger.period.id == period.id) {
          return AsyncValue<PeriodLedger>.data(ledger);
        }
      }
      return const AsyncValue<PeriodLedger>.loading();
    });
