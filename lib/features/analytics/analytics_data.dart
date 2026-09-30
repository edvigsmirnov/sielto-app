import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/analytics_repository.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/analytics/analytics_range.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Level 1: totals per category over the selected range.
final FutureProvider<List<AnalyticsSlice>> categoryTotalsProvider =
    FutureProvider<List<AnalyticsSlice>>((Ref ref) async {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const <AnalyticsSlice>[];
      final AnalyticsRange range = ref.watch(analyticsRangeProvider);
      ref.watch(spacePaymentsProvider);

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

/// Levels 2 and 3, keyed by category id or
/// [AnalyticsRepository.uncategorisedKey].
final titleTotalsProvider = FutureProvider.family<List<AnalyticsSlice>, String>(
  (Ref ref, String categoryKey) async {
    final Space? space = ref.watch(currentSpaceProvider);
    if (space == null) return const <AnalyticsSlice>[];
    final AnalyticsRange range = ref.watch(analyticsRangeProvider);
    ref.watch(spacePaymentsProvider);

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

/// Level 1 by name: totals per title across every category.
final FutureProvider<List<AnalyticsSlice>> nameTotalsProvider =
    FutureProvider<List<AnalyticsSlice>>((Ref ref) async {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const <AnalyticsSlice>[];
      final AnalyticsRange range = ref.watch(analyticsRangeProvider);
      ref.watch(spacePaymentsProvider);

      return ref
          .watch(repositoriesProvider)
          .analytics
          .byTitleAll(
            spaceId: space.id,
            from: range.from,
            to: range.to,
            expenseType: ref.watch(expenseTypeFilterProvider),
          );
    });

/// Translation key for the filter. Null is "everything".
String expenseTypeKey(ExpenseType? type) => switch (type) {
  null => 'analytics.allTypes',
  ExpenseType.mandatory => 'expenseType.mandatory',
  ExpenseType.variable => 'expenseType.variable',
};
