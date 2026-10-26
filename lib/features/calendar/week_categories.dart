import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/week_view.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Categories per day for the Week view, largest spend first, at most
/// [WeekView.maxCategoryNames].
final StreamProvider<Map<CalendarDate, List<Category>>> weekCategoriesProvider =
    StreamProvider<Map<CalendarDate, List<Category>>>((Ref ref) {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) {
        return const Stream<Map<CalendarDate, List<Category>>>.empty();
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
          .map((List<Payment> payments) => _byDay(payments, categories));
    });

Map<CalendarDate, List<Category>> _byDay(
  List<Payment> payments,
  Map<String, Category> categories,
) {
  final Map<CalendarDate, Map<Category, Decimal>> spend =
      <CalendarDate, Map<Category, Decimal>>{};
  for (final Payment p in payments) {
    final Category? category = categories[p.categoryId];
    if (category == null) continue;
    final Map<Category, Decimal> day = spend.putIfAbsent(
      p.dueDate,
      () => <Category, Decimal>{},
    );
    day[category] = (day[category] ?? Decimal.zero) + p.amount;
  }

  return <CalendarDate, List<Category>>{
    for (final MapEntry<CalendarDate, Map<Category, Decimal>> e
        in spend.entries)
      e.key:
          (e.value.keys.toList()..sort((Category a, Category b) {
                final int byAmount = e.value[b]!.compareTo(e.value[a]!);
                return byAmount != 0 ? byAmount : a.id.compareTo(b.id);
              }))
              .take(WeekView.maxCategoryNames)
              .toList(),
  };
}
