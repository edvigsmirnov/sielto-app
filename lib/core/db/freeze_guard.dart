import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/period/freeze.dart';

/// A write to a protected field of a record in a frozen period.
class PeriodFrozen implements Exception {
  const PeriodFrozen(this.periodId);

  final String periodId;

  @override
  String toString() => 'PeriodFrozen: $periodId';
}

/// Refuses edits to frozen periods. A payment's category and appended notes
/// stay editable.
class FreezeGuard {
  const FreezeGuard({
    required this.db,
    required this.clock,
    this.evaluator = const FreezeEvaluator(),
  });

  final AppDatabase db;

  final SpaceClock clock;

  final FreezeEvaluator evaluator;

  /// Throws [PeriodFrozen]. "Today" is in the Space's timezone.
  Future<void> refuseIfFrozen(String? periodId) async {
    if (periodId == null) return;

    final BudgetPeriod? period =
        await (db.select(db.budgetPeriods)
              ..where(($BudgetPeriodsTable t) => t.id.equals(periodId)))
            .getSingleOrNull();
    // A period without an end never freezes.
    if (period == null || period.endDate == null) return;

    final Space? space =
        await (db.select(db.spaces)
              ..where(($SpacesTable t) => t.id.equals(period.spaceId)))
            .getSingleOrNull();
    if (space == null) return;

    final SpaceClock spaceClock = clock.inZone(space.timezone);
    final bool frozen = evaluator.isFrozen(
      endDate: period.endDate,
      today: spaceClock.today(),
      nowUtc: spaceClock.nowUtc(),
      unfrozenUntil: period.unfrozenUntil,
    );
    if (frozen) throw PeriodFrozen(periodId);
  }

  Future<FreezeState> stateOf(String? periodId) async {
    if (periodId == null) return FreezeState.open;

    final BudgetPeriod? period =
        await (db.select(db.budgetPeriods)
              ..where(($BudgetPeriodsTable t) => t.id.equals(periodId)))
            .getSingleOrNull();
    if (period == null || period.endDate == null) return FreezeState.open;

    final Space? space =
        await (db.select(db.spaces)
              ..where(($SpacesTable t) => t.id.equals(period.spaceId)))
            .getSingleOrNull();
    if (space == null) return FreezeState.open;

    final SpaceClock spaceClock = clock.inZone(space.timezone);
    return evaluator.evaluate(
      endDate: period.endDate,
      today: spaceClock.today(),
      nowUtc: spaceClock.nowUtc(),
      unfrozenUntil: period.unfrozenUntil,
    );
  }
}
