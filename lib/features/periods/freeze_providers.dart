import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Freeze state of every period of the open Space, for screens. Uses the same
/// [FreezeEvaluator] as the repositories.
@immutable
class FreezeLookup {
  const FreezeLookup({
    required this.periods,
    required this.today,
    required this.nowUtc,
    this.evaluator = const FreezeEvaluator(),
  });

  final Map<String, BudgetPeriod> periods;
  final CalendarDate today;
  final DateTime nowUtc;
  final FreezeEvaluator evaluator;

  /// Open for unbound records and continuous periods.
  FreezeState of(String? periodId) {
    final BudgetPeriod? period = periodId == null ? null : periods[periodId];
    if (period == null) return FreezeState.open;
    return stateOf(period);
  }

  FreezeState stateOf(BudgetPeriod period) => evaluator.evaluate(
    endDate: period.endDate,
    today: today,
    nowUtc: nowUtc,
    unfrozenUntil: period.unfrozenUntil,
  );

  bool isFrozen(String? periodId) => of(periodId) == FreezeState.frozen;

  /// Negative once frozen.
  int daysUntilFreeze(BudgetPeriod period) {
    final CalendarDate? end = period.endDate;
    if (end == null) return 1 << 30;
    return today.daysUntil(end.addDays(evaluator.freezeAfterDays));
  }
}

final Provider<FreezeLookup> freezeLookupProvider = Provider<FreezeLookup>((
  Ref ref,
) {
  final SpaceClock clock = ref.watch(spaceClockProvider);
  return FreezeLookup(
    periods: <String, BudgetPeriod>{
      for (final BudgetPeriod p
          in ref.watch(spacePeriodsProvider).value ?? const <BudgetPeriod>[])
        p.id: p,
    },
    today: clock.today(),
    nowUtc: clock.nowUtc(),
  );
});
