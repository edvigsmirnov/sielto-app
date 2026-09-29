import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/week_view.dart';
import 'package:sielto/features/categories/category_title.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Category names per day for the Week view, largest spend first, at most
/// [WeekView.maxCategoryNames]. Uncategorised payments are skipped.
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

  // Includes soft-deleted categories.
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
    final String? title = categories[id]?.shownTitle;
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
                return byAmount != 0 ? byAmount : a.compareTo(b);
              }))
              .take(WeekView.maxCategoryNames)
              .toList(),
  };
}
