import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/ledger/available_money.dart';
import 'package:sielto/domain/ledger/ledger_entry.dart';
import 'package:sielto/domain/ledger/ledger_walker.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Live payments of the open Space.
final StreamProvider<List<Payment>> spacePaymentsProvider =
    StreamProvider<List<Payment>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const Stream<List<Payment>>.empty();
      return ref.watch(repositoriesProvider).payments.watchInSpace(space.id);
    });

final StreamProvider<List<Income>> spaceIncomesProvider =
    StreamProvider<List<Income>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const Stream<List<Income>>.empty();
      return ref.watch(repositoriesProvider).incomes.watchInSpace(space.id);
    });

final StreamProvider<List<IncomeRecurrenceRule>> incomeRulesProvider =
    StreamProvider<List<IncomeRecurrenceRule>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) {
        return const Stream<List<IncomeRecurrenceRule>>.empty();
      }
      return ref.watch(repositoriesProvider).incomeRules.watchInSpace(space.id);
    });

final StreamProvider<List<Category>> spaceCategoriesProvider =
    StreamProvider<List<Category>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const Stream<List<Category>>.empty();
      return ref.watch(repositoriesProvider).categories.watchInSpace(space.id);
    });

/// Includes soft-deleted categories.
final StreamProvider<Map<String, Category>> categoryIndexProvider =
    StreamProvider<Map<String, Category>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const Stream<Map<String, Category>>.empty();
      return ref
          .watch(repositoriesProvider)
          .categories
          .watchAllEverInSpace(space.id)
          .map(
            (List<Category> rows) => <String, Category>{
              for (final Category c in rows) c.id: c,
            },
          );
    });

LedgerEntry paymentEntry(Payment p) => LedgerEntry(
  id: p.id,
  date: p.dueDate,
  amount: p.amount,
  isIncome: false,
  sortOrder: p.sortOrder,
  expenseType: p.expenseType,
  isPaid: p.isPaid,
  title: p.title,
);

/// Null for an income without an amount.
LedgerEntry? incomeEntry(Income i) {
  final Decimal? amount = i.amount;
  if (amount == null) return null;
  return LedgerEntry(
    id: i.id,
    date: i.expectedDate,
    amount: amount,
    isIncome: true,
    sortOrder: i.sortOrder,
    isPaid: i.isPaid,
    title: i.title,
  );
}

/// Flow Space figures, shared by every screen.
@immutable
class FlowLedger {
  const FlowLedger({
    required this.available,
    required this.cascade,
    required this.entries,
    required this.excludedCount,
    required this.today,
    required this.totalPlanned,
    required this.totalPaid,
    required this.nearestIncome,
  });

  /// Manual balance plus incomes received since it was set.
  final Decimal available;

  final LedgerCascade cascade;

  /// Entries after the double-count rule.
  final List<LedgerEntry> entries;

  /// Rows excluded by that rule.
  final int excludedCount;

  final CalendarDate today;

  /// Every planned expense, paid or not.
  final Decimal totalPlanned;
  final Decimal totalPaid;

  /// Next income not yet arrived.
  final Income? nearestIncome;

  Decimal get totalRemaining => totalPlanned - totalPaid;

  Coverage? get coverage => cascade.coverage;

  /// Null when not covered.
  Decimal? get freeCash => cascade.all.freeCash;

  /// After mandatory expenses only.
  Decimal? get baseRemainder => cascade.mandatory.freeCash;

  /// Null while the money reaches everything.
  CalendarDate? get lastCoveredDay => cascade.lastCoveredDay;

  Map<String, bool> get coverageByEntry => <String, bool>{
    for (final LedgerStep step in cascade.all.steps)
      step.entry.id: step.isCovered,
  };
}

extension BalanceDay on Space {
  /// Day of the balance snapshot in the Space's timezone.
  CalendarDate? get balanceSetOn => manualBalanceUpdatedAt == null
      ? null
      : SpaceClock(timezone: timezone).dateOf(manualBalanceUpdatedAt!);
}

/// Incomes dated on or before the balance snapshot are part of it; later ones
/// are added.
FlowLedger buildFlowLedger({
  required Space space,
  required List<Payment> payments,
  required List<Income> incomes,
  required CalendarDate today,
}) {
  final CalendarDate? balanceSetOn = space.balanceSetOn;
  final Decimal manualBalance = space.manualBalance ?? Decimal.zero;

  Decimal receivedSinceSnapshot = Decimal.zero;
  final List<LedgerEntry> entries = <LedgerEntry>[];

  for (final Payment p in payments) {
    entries.add(paymentEntry(p));
  }

  for (final Income i in incomes) {
    final LedgerEntry? entry = incomeEntry(i);
    if (entry == null) continue;
    if (!i.isPaid) {
      entries.add(entry);
      continue;
    }
    final bool insideSnapshot =
        balanceSetOn != null && !entry.date.isAfter(balanceSetOn);
    if (!insideSnapshot) receivedSinceSnapshot += entry.amount;
  }

  final LedgerContext context = FlowContext.build(
    manualBalance: manualBalance + receivedSinceSnapshot,
    entries: entries,
    balanceSetOn: balanceSetOn,
  );

  Decimal planned = Decimal.zero;
  Decimal paid = Decimal.zero;
  for (final Payment p in payments) {
    planned += p.amount;
    if (p.isPaid) paid += p.amount;
  }

  Income? nearest;
  for (final Income i in incomes) {
    if (i.isPaid || i.expectedDate.isBefore(today)) continue;
    if (nearest == null || i.expectedDate.isBefore(nearest.expectedDate)) {
      nearest = i;
    }
  }

  return FlowLedger(
    available: context.available,
    cascade: LedgerWalker.cascade(
      available: context.available,
      entries: context.entries,
    ),
    entries: context.entries,
    excludedCount: FlowContext.excludedCount(
      entries: entries,
      balanceSetOn: balanceSetOn,
    ),
    today: today,
    totalPlanned: planned,
    totalPaid: paid,
    nearestIncome: nearest,
  );
}

/// The walk with a draft added, in memory. [replacingId] removes the record
/// being edited.
LedgerRun previewRun({
  required Decimal available,
  required List<LedgerEntry> entries,
  required List<LedgerEntry> draft,
  String? replacingId,
}) => LedgerWalker.walk(
  available: available,
  entries: <LedgerEntry>[
    for (final LedgerEntry e in entries)
      if (e.id != replacingId) e,
    ...draft,
  ],
);

final Provider<AsyncValue<FlowLedger>> flowLedgerProvider =
    Provider<AsyncValue<FlowLedger>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const AsyncValue<FlowLedger>.loading();

      final AsyncValue<List<Payment>> payments = ref.watch(
        spacePaymentsProvider,
      );
      final AsyncValue<List<Income>> incomes = ref.watch(spaceIncomesProvider);

      final Object? error = payments.error ?? incomes.error;
      if (error != null) {
        return AsyncValue<FlowLedger>.error(
          error,
          payments.stackTrace ?? incomes.stackTrace ?? StackTrace.current,
        );
      }

      final List<Payment>? paymentRows = payments.value;
      final List<Income>? incomeRows = incomes.value;
      if (paymentRows == null || incomeRows == null) {
        return const AsyncValue<FlowLedger>.loading();
      }

      return AsyncValue<FlowLedger>.data(
        buildFlowLedger(
          space: space,
          payments: paymentRows,
          incomes: incomeRows,
          today: ref.watch(spaceClockProvider).today(),
        ),
      );
    });
