import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';

/// The aggregate figures the Month and Week views draw (spec 8.1).
///
/// One grouping query per range, live. Keyed by view rather than by date so
/// stepping a month reuses the same provider instead of leaving a cache entry
/// behind for every month ever visited.
///
/// The type is inferred: `flutter_riverpod` does not export
/// `StreamProviderFamily`.
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

/// The Year view: the same figures grouped by month, keyed by the first of
/// each (spec 8.1).
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

/// One day's payments and incomes, live (spec 8.1).
///
/// The detail queries, and they run only while the Day view is on screen — the
/// aggregate views never reach for them.
///
/// The types are inferred: `flutter_riverpod` does not export
/// `StreamProviderFamily`.
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

/// Both tables as one value, or null until both have arrived.
///
/// Null rather than an `AsyncValue` pair: the screen has one loading state,
/// and two `AsyncValue`s to unwrap at every call site is the shape the Feed
/// already avoids.
final dayRecordsProvider = Provider.family<DayRecords?, CalendarDate>((
  Ref ref,
  CalendarDate day,
) {
  final List<Payment>? payments = ref.watch(dayPaymentsProvider(day)).value;
  final List<Income>? incomes = ref.watch(dayIncomesProvider(day)).value;
  if (payments == null || incomes == null) return null;
  return DayRecords(payments: payments, incomes: incomes);
});

/// What one day holds.
@immutable
class DayRecords {
  const DayRecords({required this.payments, required this.incomes});

  final List<Payment> payments;
  final List<Income> incomes;

  bool get isEmpty => payments.isEmpty && incomes.isEmpty;
}
