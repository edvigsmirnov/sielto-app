import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:sielto/domain/ledger/ledger_entry.dart';
import 'package:sielto/domain/value/calendar_date.dart';

enum Coverage {
  /// Money left over.
  covered,

  /// Covered exactly.
  exact,

  /// Something falls past the cutoff.
  short,
}

@immutable
class LedgerStep {
  const LedgerStep({
    required this.entry,
    required this.balanceAfter,
    required this.isCovered,
  });

  final LedgerEntry entry;

  /// Keeps going negative past the cutoff.
  final Decimal balanceAfter;

  /// False for this entry and every expense after it.
  final bool isCovered;
}

@immutable
class LedgerRun {
  const LedgerRun({
    required this.available,
    required this.steps,
    required this.finalBalance,
    required this.cutoffEntryId,
    required this.cutoffDate,
    required this.exhaustedEntryId,
    required this.exhaustedDate,
    required this.coverage,
  });

  final Decimal available;

  final List<LedgerStep> steps;

  /// Negative means overspend.
  final Decimal finalBalance;

  /// First expense that cannot be paid. Null when everything fits.
  final String? cutoffEntryId;

  final CalendarDate? cutoffDate;

  /// Expense that leaves exactly zero, before any cutoff.
  final String? exhaustedEntryId;

  final CalendarDate? exhaustedDate;

  final Coverage coverage;

  bool get hasCutoff => cutoffEntryId != null;

  /// Row that the "money runs out" line attaches to: above the cutoff expense,
  /// or below the one that leaves zero.
  ({String entryId, bool below})? get moneyEndsAt {
    final String? exhausted = exhaustedEntryId;
    if (exhausted != null) return (entryId: exhausted, below: true);
    final String? cutoff = cutoffEntryId;
    if (cutoff != null) return (entryId: cutoff, below: false);
    return null;
  }

  /// Last day the money reaches, the day before any cutoff; null when it
  /// reaches everything.
  CalendarDate? get lastCoveredDay => cutoffDate?.addDays(-1) ?? exhaustedDate;

  /// Null once there is a cutoff.
  Decimal? get freeCash => hasCutoff ? null : finalBalance;
}

/// Chronological running balance. A future income joins only on its own date,
/// so the cutoff can fall before it. Expects entries already filtered.
abstract final class LedgerWalker {
  static LedgerRun walk({
    required Decimal available,
    required List<LedgerEntry> entries,
  }) {
    final List<LedgerEntry> ordered = List<LedgerEntry>.of(entries)
      ..sort(compareLedgerEntries);

    Decimal balance = available;
    String? cutoffEntryId;
    CalendarDate? cutoffDate;
    String? exhaustedEntryId;
    CalendarDate? exhaustedDate;
    final List<LedgerStep> steps = <LedgerStep>[];

    for (final LedgerEntry entry in ordered) {
      if (entry.isIncome) {
        balance += entry.amount;
        steps.add(
          LedgerStep(entry: entry, balanceAfter: balance, isCovered: true),
        );
        continue;
      }

      final Decimal after = balance - entry.amount;
      // Zero is covered.
      final bool covered = cutoffEntryId == null && after >= Decimal.zero;
      if (!covered && cutoffEntryId == null) {
        cutoffEntryId = entry.id;
        cutoffDate = entry.date;
      }
      if (covered &&
          after == Decimal.zero &&
          exhaustedEntryId == null &&
          cutoffEntryId == null) {
        exhaustedEntryId = entry.id;
        exhaustedDate = entry.date;
      }

      balance = after;
      steps.add(
        LedgerStep(entry: entry, balanceAfter: balance, isCovered: covered),
      );
    }

    return LedgerRun(
      available: available,
      steps: steps,
      finalBalance: balance,
      cutoffEntryId: cutoffEntryId,
      cutoffDate: cutoffDate,
      exhaustedEntryId: exhaustedEntryId,
      exhaustedDate: exhaustedDate,
      coverage: _coverage(
        hasCutoff: cutoffEntryId != null,
        finalBalance: balance,
      ),
    );
  }

  /// Walks mandatory expenses alone, then everything. Incomes join both.
  static LedgerCascade cascade({
    required Decimal available,
    required List<LedgerEntry> entries,
  }) {
    final List<LedgerEntry> mandatoryOnly = entries
        .where((LedgerEntry e) => e.isIncome || e.isMandatory)
        .toList();
    return LedgerCascade(
      mandatory: walk(available: available, entries: mandatoryOnly),
      all: walk(available: available, entries: entries),
    );
  }

  static Coverage _coverage({
    required bool hasCutoff,
    required Decimal finalBalance,
  }) {
    if (hasCutoff || finalBalance < Decimal.zero) return Coverage.short;
    if (finalBalance == Decimal.zero) return Coverage.exact;
    return Coverage.covered;
  }
}

@immutable
class LedgerCascade {
  const LedgerCascade({required this.mandatory, required this.all});

  /// Mandatory expenses only.
  final LedgerRun mandatory;

  /// Mandatory and variable.
  final LedgerRun all;

  /// From the full run. Null when there is no money and nothing planned.
  Coverage? get coverage => hasData ? all.coverage : null;

  bool get hasData => all.available != Decimal.zero || all.steps.isNotEmpty;

  ({String entryId, bool below})? get moneyEndsAt => all.moneyEndsAt;

  CalendarDate? get lastCoveredDay => all.lastCoveredDay;
}
