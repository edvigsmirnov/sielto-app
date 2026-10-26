import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/feed/feed_model.dart';

/// Month and Week sums, one query per range. Type inferred: `flutter_riverpod`
/// does not export `StreamProviderFamily`.
final dailyTotalsProvider =
    StreamProvider.family<Map<CalendarDate, DayTotals>, CalendarView>((
      Ref ref,
      CalendarView view,
    ) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) {
        return const Stream<Map<CalendarDate, DayTotals>>.empty();
      }
      final ({CalendarDate from, CalendarDate to}) range = rangeOf(
        view,
        ref.watch(selectedDateProvider),
      );
      return ref
          .watch(repositoriesProvider)
          .calendar
          .watchDailyTotals(space.id, range.from, range.to);
    });

/// Year view sums, keyed by the first of each month.
final StreamProvider<Map<CalendarDate, DayTotals>> monthlyTotalsProvider =
    StreamProvider<Map<CalendarDate, DayTotals>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) {
        return const Stream<Map<CalendarDate, DayTotals>>.empty();
      }
      return ref
          .watch(repositoriesProvider)
          .calendar
          .watchMonthlyTotals(space.id, ref.watch(selectedDateProvider).year);
    });

/// One day's payments and incomes, for the Day view.
final dayPaymentsProvider = StreamProvider.family<List<Payment>, CalendarDate>((
  Ref ref,
  CalendarDate day,
) {
  final Space? space = ref.watch(currentSpaceProvider);
  if (space == null) return const Stream<List<Payment>>.empty();
  return ref.watch(repositoriesProvider).payments.watchOnDay(space.id, day);
});

final dayIncomesProvider = StreamProvider.family<List<Income>, CalendarDate>((
  Ref ref,
  CalendarDate day,
) {
  final Space? space = ref.watch(currentSpaceProvider);
  if (space == null) return const Stream<List<Income>>.empty();
  return ref.watch(repositoriesProvider).incomes.watchOnDay(space.id, day);
});

/// Null until both tables have loaded.
final dayRecordsProvider = Provider.family<DayRecords?, CalendarDate>((
  Ref ref,
  CalendarDate day,
) {
  final List<Payment>? payments = ref.watch(dayPaymentsProvider(day)).value;
  final List<Income>? incomes = ref.watch(dayIncomesProvider(day)).value;
  final Space? space = ref.watch(currentSpaceProvider);
  if (payments == null || incomes == null || space == null) return null;
  return DayRecords(
    <FeedRecord>[
      for (final Payment p in payments) FeedRecord.fromPayment(p),
      for (final Income i in incomes) FeedRecord.fromIncome(i),
    ]..sort(
      (FeedRecord a, FeedRecord b) => compareInDay(a, b, space.feedOrderMode),
    ),
  );
});

/// One day's records in Feed order, with their sums.
@immutable
class DayRecords {
  factory DayRecords(List<FeedRecord> rows) {
    Decimal expenses = Decimal.zero;
    Decimal income = Decimal.zero;
    for (final FeedRecord r in rows) {
      final Decimal amount = r.amount ?? Decimal.zero;
      if (r.isIncome) {
        income += amount;
      } else {
        expenses += amount;
      }
    }
    return DayRecords._(rows, expenses: expenses, income: income);
  }

  const DayRecords._(this.rows, {required this.expenses, required this.income});

  final List<FeedRecord> rows;
  final Decimal expenses;
  final Decimal income;
}
