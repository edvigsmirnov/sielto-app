import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/analytics_repository.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/analytics/analytics_range.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// What a level shows: titles or categories, within one category or all.
typedef SliceQuery = ({bool byTitle, String? categoryKey});

/// Totals over the selected range; reruns on any payment change.
final analyticsSlicesProvider =
    FutureProvider.family<List<AnalyticsSlice>, SliceQuery>((
      Ref ref,
      SliceQuery query,
    ) async {
      final Space? space = ref.watch(currentSpaceProvider);
      if (space == null) return const <AnalyticsSlice>[];
      final AnalyticsRange range = ref.watch(analyticsRangeProvider);
      ref.watch(spacePaymentsProvider);

      return ref
          .watch(repositoriesProvider)
          .analytics
          .slices(
            spaceId: space.id,
            from: range.from,
            to: range.to,
            expenseType: ref.watch(expenseTypeFilterProvider),
            byTitle: query.byTitle,
            categoryKey: query.categoryKey,
          );
    });

/// Translation key for the filter. Null is "everything".
String expenseTypeKey(ExpenseType? type) => switch (type) {
  null => 'analytics.allTypes',
  ExpenseType.mandatory => 'expenseType.mandatory',
  ExpenseType.variable => 'expenseType.variable',
};
