import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/feed/feed_filter.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/feed/feed_window.dart';
import 'package:sielto/features/space/budget_ledger.dart';
import 'package:sielto/features/space/period_ledger.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// What the Feed draws, in any mode.
@immutable
class FeedSource {
  const FeedSource({
    required this.records,
    required this.today,
    required this.coverage,
    required this.moneyEndsAt,
    required this.available,
    required this.freeCash,
    required this.paid,
    required this.remaining,
    required this.mode,
    this.byPeriod = false,
    this.emptyPeriodStarts = const <CalendarDate>[],
    this.beyondDeadline = const <String>{},
    this.hasIncome = true,
    this.leftAfter = const <String, Decimal>{},
  });

  /// The records in the render window.
  final List<FeedRecord> records;
  final CalendarDate today;
  final Map<String, bool> coverage;

  /// Left to spend after each entry.
  final Map<String, Decimal> leftAfter;

  /// Row id to the side of the row where the cutoff falls.
  final Map<String, bool> moneyEndsAt;

  /// Null when the anchor income has no amount.
  final Decimal? available;

  /// Null when not covered or [available] is unknown.
  final Decimal? freeCash;

  final Decimal paid;
  final Decimal remaining;

  /// The figures follow the selected period.
  final bool byPeriod;

  /// Periods in the render window with no entries, so the selector can
  /// still scroll to them.
  final List<CalendarDate> emptyPeriodStarts;

  final BudgetMode mode;

  /// Dimmed and excluded.
  final Set<String> beyondDeadline;

  /// False for a cycle with no income; free money is then zero.
  final bool hasIncome;

  /// Free money as shown: zero in a cycle with no income.
  Decimal? get free => hasIncome ? freeCash : Decimal.zero;

  /// The money runs out before the cycle ends.
  bool get runsShort => free == null && available != null;

  String get availableLabel => switch (mode) {
    BudgetMode.incomeDriven => 'feed.income',
    BudgetMode.flow => 'feed.currentMoney',
    BudgetMode.budget => 'budget.fund',
  };

  /// The Dashboard's name for [freeCash].
  String get freeLabel =>
      mode == BudgetMode.budget ? 'budget.remaining' : 'dashboard.freeMoney';
}

/// The list and its figures; null while loading. One continuous list in
/// every mode; only the figures follow the selected period.
final Provider<FeedSource?> feedSourceProvider = Provider<FeedSource?>((
  Ref ref,
) {
  final Space? space = ref.watch(currentSpaceProvider);
  final List<Payment>? payments = ref.watch(spacePaymentsProvider).value;
  final List<Income>? incomes = ref.watch(spaceIncomesProvider).value;
  final FeedWindow window = ref.watch(feedWindowProvider);
  if (space == null || payments == null || incomes == null) return null;
  // Right after a Space switch the lists still hold the previous Space.
  if (payments.firstOrNull?.spaceId case final String id when id != space.id) {
    return null;
  }
  if (incomes.firstOrNull?.spaceId case final String id when id != space.id) {
    return null;
  }

  final List<FeedRecord> records = <FeedRecord>[
    for (final Payment p in payments)
      if (window.contains(p.dueDate)) FeedRecord.fromPayment(p),
    for (final Income i in incomes)
      if (window.contains(i.expectedDate)) FeedRecord.fromIncome(i),
  ];

  if (space.budgetMode == BudgetMode.incomeDriven) {
    final List<PeriodLedger> ledgers =
        ref.watch(periodLedgersProvider).value ?? const <PeriodLedger>[];
    final PeriodLedger? selected = ref.watch(periodLedgerProvider).value;
    final Map<String, bool> coverage = <String, bool>{};
    final Map<String, bool> endsAt = <String, bool>{};
    final Map<String, Decimal> left = <String, Decimal>{};
    for (final PeriodLedger ledger in ledgers) {
      coverage.addAll(ledger.coverageByEntry);
      left.addAll(ledger.balanceByEntry);
      if (ledger.moneyEndsAt case final ({String entryId, bool below}) end) {
        endsAt[end.entryId] = end.below;
      }
    }

    // No periods before the first regular income.
    if (selected == null) {
      return FeedSource(
        records: records,
        today: ref.watch(spaceClockProvider).today(),
        coverage: coverage,
        moneyEndsAt: endsAt,
        available: Decimal.zero,
        freeCash: null,
        paid: Decimal.zero,
        remaining: Decimal.zero,
        mode: space.budgetMode,
        hasIncome: false,
      );
    }

    return FeedSource(
      records: records,
      today: selected.today,
      coverage: coverage,
      leftAfter: left,
      moneyEndsAt: endsAt,
      available: selected.anchorAmount,
      freeCash: selected.freeCash,
      paid: selected.totalPaid,
      remaining: selected.totalRemaining,
      byPeriod: true,
      emptyPeriodStarts: <CalendarDate>[
        for (final BudgetPeriod p in ref.watch(incomePeriodsProvider))
          if (window.contains(p.startDate) &&
              !records.any(
                (FeedRecord r) =>
                    !r.date.isBefore(p.startDate) &&
                    (p.endDate == null || !r.date.isAfter(p.endDate!)),
              ))
            p.startDate,
      ],
      mode: space.budgetMode,
      hasIncome: selected.hasIncome,
    );
  }

  final SpaceLedger? ledger = space.budgetMode == BudgetMode.budget
      ? ref.watch(budgetLedgerProvider).value
      : ref.watch(flowLedgerProvider).value;
  if (ledger == null) return null;
  final BudgetLedger? budget = ledger is BudgetLedger ? ledger : null;
  final ({String entryId, bool below})? end = ledger.moneyEndsAt;
  return FeedSource(
    records: records,
    today: ledger.today,
    coverage: ledger.coverageByEntry,
    leftAfter: ledger.balanceByEntry,
    moneyEndsAt: <String, bool>{if (end != null) end.entryId: end.below},
    available: ledger.available,
    // Without a fund the Budget figure is what was spent.
    freeCash: budget?.hasFund ?? true ? ledger.freeCash : ledger.available,
    paid: ledger.totalPaid,
    remaining: ledger.totalRemaining,
    mode: space.budgetMode,
    beyondDeadline: budget?.beyondDeadline ?? const <String>{},
  );
});

/// Every record [filter] matches, outside the render window too.
List<FeedRecord> feedMatches(WidgetRef ref, FeedFilter filter) => <FeedRecord>[
  for (final Payment p
      in ref.read(spacePaymentsProvider).value ?? const <Payment>[])
    if (filter.matches(FeedRecord.fromPayment(p))) FeedRecord.fromPayment(p),
  for (final Income i
      in ref.read(spaceIncomesProvider).value ?? const <Income>[])
    if (filter.matches(FeedRecord.fromIncome(i))) FeedRecord.fromIncome(i),
];
