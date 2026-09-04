import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/analytics_repository.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/analytics/analytics_range.dart';

/// Level 1: what each category cost over the selected range (spec 8.2).
///
/// Rebuilt when the range or the type filter changes, and — because it watches
/// the payments stream — when a record is edited while Analytics is open.
final FutureProvider<List<AnalyticsSlice>> categoryTotalsProvider =
    FutureProvider<List<AnalyticsSlice>>((Ref ref) async {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const <AnalyticsSlice>[];
      final AnalyticsRange range = ref.watch(analyticsRangeProvider);

      return ref
          .watch(repositoriesProvider)
          .analytics
          .byCategory(
            spaceId: space.id,
            from: range.from,
            to: range.to,
            expenseType: ref.watch(expenseTypeFilterProvider),
          );
    });

/// Levels 2 and 3: what each title cost inside one category.
///
/// Keyed by category id, with the empty string standing for the uncategorised
/// slice — the same key [AnalyticsRepository.uncategorisedKey] uses, so the
/// level-1 row can hand its own key straight through.
///
/// The type is inferred: `flutter_riverpod` does not export
/// `FutureProviderFamily`.
final titleTotalsProvider = FutureProvider.family<List<AnalyticsSlice>, String>(
  (Ref ref, String categoryKey) async {
    final Space? space = ref.watch(currentSpaceProvider);
    if (space == null) return const <AnalyticsSlice>[];
    final AnalyticsRange range = ref.watch(analyticsRangeProvider);

    return ref
        .watch(repositoriesProvider)
        .analytics
        .byTitle(
          spaceId: space.id,
          from: range.from,
          to: range.to,
          categoryId: categoryKey == AnalyticsRepository.uncategorisedKey
              ? null
              : categoryKey,
          expenseType: ref.watch(expenseTypeFilterProvider),
        );
  },
);

/// The filter as the label the screens print. Null is "everything", and that
/// is a state worth naming rather than leaving blank.
String expenseTypeKey(ExpenseType? type) => switch (type) {
  null => 'analytics.allTypes',
  ExpenseType.mandatory => 'expenseType.mandatory',
  ExpenseType.variable => 'expenseType.variable',
};
