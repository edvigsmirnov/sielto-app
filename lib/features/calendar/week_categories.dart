import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/week_view.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// The category names the Week view puts under each date (spec 8.1).
///
/// The one place the Calendar reads rows outside the Day view, and it is worth
/// it: a week is seven days, and the names are what make a week row say
/// something a month cell cannot. The Month view gets none of this — forty-two
/// days of titles is the detail load the aggregate query exists to avoid.
///
/// Largest spend first, capped at [WeekView.maxCategoryNames]. Uncategorised
/// payments contribute nothing rather than a placeholder name.
final StreamProvider<Map<CalendarDate, List<String>>>
weekCategoryNamesProvider = StreamProvider<Map<CalendarDate, List<String>>>((
  Ref ref,
) {
  final Space? space = ref.watch(currentSpaceProvider);
  if (space == null) {
    return const Stream<Map<CalendarDate, List<String>>>.empty();
  }

  final ({CalendarDate from, CalendarDate to}) week = rangeOf(
    CalendarView.week,
    ref.watch(selectedDateProvider),
  );

  // Categories can be soft-deleted and a payment keeps showing the one it
  // was filed under, so this reads the index that includes them (spec 7).
  final Map<String, Category> categories =
      ref.watch(categoryIndexProvider).value ?? const <String, Category>{};

  return ref
      .watch(repositoriesProvider)
      .payments
      .watchAround(space.id, week.from, week.to)
      .map((List<Payment> payments) => _namesByDay(payments, categories));
});

Map<CalendarDate, List<String>> _namesByDay(
  List<Payment> payments,
  Map<String, Category> categories,
) {
  final Map<CalendarDate, Map<String, Decimal>> spend =
      <CalendarDate, Map<String, Decimal>>{};
  for (final Payment p in payments) {
    final String? id = p.categoryId;
    if (id == null) continue;
    final String? title = categories[id]?.title;
    if (title == null) continue;
    final Map<String, Decimal> day = spend.putIfAbsent(
      p.dueDate,
      () => <String, Decimal>{},
    );
    day[title] = (day[title] ?? Decimal.zero) + p.amount;
  }

  return <CalendarDate, List<String>>{
    for (final MapEntry<CalendarDate, Map<String, Decimal>> e in spend.entries)
      e.key:
          (e.value.keys.toList()..sort((String a, String b) {
                final int byAmount = e.value[b]!.compareTo(e.value[a]!);
                // Ties break on the name, so the row does not reshuffle between
                // rebuilds.
                return byAmount != 0 ? byAmount : a.compareTo(b);
              }))
              .take(WeekView.maxCategoryNames)
              .toList(),
  };
}
