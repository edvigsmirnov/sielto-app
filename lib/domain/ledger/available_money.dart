import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:sielto/domain/ledger/ledger_entry.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// The walk's starting sum and the entries it sees. The only difference
/// between modes.
@immutable
class LedgerContext {
  const LedgerContext({required this.available, required this.entries});

  final Decimal available;
  final List<LedgerEntry> entries;
}

/// Income-driven mode: anchor amount plus arrived secondary incomes, minus the
/// period's payments. Future incomes join on their own dates.
@immutable
class IncomeDrivenContext {
  const IncomeDrivenContext({
    required this.anchorAmount,
    required this.arrivedSecondary,
    required this.entries,
  });

  /// Null when the anchor income has no amount.
  final Decimal? anchorAmount;

  /// Non-anchor incomes already received in this period.
  final Decimal arrivedSecondary;

  final List<LedgerEntry> entries;

  bool get isComputable => anchorAmount != null;

  LedgerContext? toLedgerContext() {
    final Decimal? anchor = anchorAmount;
    if (anchor == null) return null;
    return LedgerContext(
      available: anchor + arrivedSecondary,
      entries: entries,
    );
  }
}

/// Flow mode. Excludes expenses paid and due on or before the balance
/// snapshot day: the balance already reflects them.
abstract final class FlowContext {
  static LedgerContext build({
    required Decimal manualBalance,
    required List<LedgerEntry> entries,
    CalendarDate? balanceSetOn,
  }) {
    final List<LedgerEntry> kept = balanceSetOn == null
        ? entries
        : entries
              .where((LedgerEntry e) => !_alreadyInBalance(e, balanceSetOn))
              .toList();
    return LedgerContext(available: manualBalance, entries: kept);
  }

  static int excludedCount({
    required List<LedgerEntry> entries,
    CalendarDate? balanceSetOn,
  }) {
    if (balanceSetOn == null) return 0;
    return entries
        .where((LedgerEntry e) => _alreadyInBalance(e, balanceSetOn))
        .length;
  }

  static bool _alreadyInBalance(LedgerEntry entry, CalendarDate balanceSetOn) =>
      entry.isExpense && entry.isPaid && !entry.date.isAfter(balanceSetOn);
}

/// Budget mode: `budget_target` plus contributions. Target and deadline are
/// optional and independent.
@immutable
class BudgetContext {
  const BudgetContext({
    required this.budgetTarget,
    required this.contributions,
    required this.entries,
    this.deadlineDate,
    this.deadlineIsHard = false,
  });

  final Decimal? budgetTarget;

  /// Incomes recorded against the fund.
  final Decimal contributions;

  final List<LedgerEntry> entries;
  final CalendarDate? deadlineDate;
  final bool deadlineIsHard;

  bool get hasFund => budgetTarget != null;

  LedgerContext? toLedgerContext() {
    final Decimal? target = budgetTarget;
    if (target == null) return null;
    return LedgerContext(available: target + contributions, entries: entries);
  }

  /// Entries after a hard deadline. Excluded from the fit, not deleted. A soft
  /// deadline marks nothing.
  List<LedgerEntry> get beyondDeadline {
    final CalendarDate? deadline = deadlineDate;
    if (deadline == null || !deadlineIsHard) return const <LedgerEntry>[];
    return entries.where((LedgerEntry e) => e.date.isAfter(deadline)).toList();
  }

  /// A soft deadline never blocks input.
  bool acceptsEntryOn(CalendarDate date) {
    final CalendarDate? deadline = deadlineDate;
    if (deadline == null || !deadlineIsHard) return true;
    return !date.isAfter(deadline);
  }
}
