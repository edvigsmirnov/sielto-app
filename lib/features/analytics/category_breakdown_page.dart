import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/analytics_repository.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/analytics/analytics_data.dart';
import 'package:sielto/features/analytics/analytics_parts.dart';
import 'package:sielto/features/analytics/category_averages_page.dart';

/// Analytics level 2: one category, broken down by title (spec 8.2).
///
/// A back arrow, not a cross: levels 2 and 3 move inside the analytics stack
/// and only level 1 closes it (design section 11).
class CategoryBreakdownPage extends ConsumerWidget {
  const CategoryBreakdownPage({
    required this.categoryKey,
    required this.title,
    super.key,
  });

  /// The category id, or [AnalyticsRepository.uncategorisedKey] for the slice
  /// of payments filed under nothing.
  final String categoryKey;

  final String title;

  static Future<void> open(
    BuildContext context, {
    required String categoryKey,
    required String title,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext _) =>
          CategoryBreakdownPage(categoryKey: categoryKey, title: title),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Space space = ref.space;
    final MoneyFormat money = MoneyFormat(
      locale: context.locale.toString(),
      currencyCode: space.currencyCode,
    );
    final List<AnalyticsSlice> slices =
        ref.watch(titleTotalsProvider(categoryKey)).value ??
        const <AnalyticsSlice>[];
    final Decimal total = slices.fold(
      Decimal.zero,
      (Decimal sum, AnalyticsSlice s) => sum + s.total,
    );

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(
        backgroundColor: context.sage.surface,
        title: Text(title, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
          children: <Widget>[
            const RangeCaption(),
            const SizedBox(height: SageSpace.xs),
            Center(
              child: Text(
                money.format(total),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: SageSpace.lg),
            if (slices.isEmpty)
              EmptyState(message: tr('analytics.empty'))
            else ...<Widget>[
              for (final AnalyticsSlice slice in slices)
                SliceRow(label: slice.label, value: money.format(slice.total)),
              const SizedBox(height: SageSpace.md),
              // Level 3 is the same rows read as averages, so it hangs off the
              // bottom of this list rather than sitting in the header.
              _AveragesLink(
                onTap: () => CategoryAveragesPage.open(
                  context,
                  categoryKey: categoryKey,
                  title: title,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AveragesLink extends StatelessWidget {
  const _AveragesLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                tr('analytics.averagesLink'),
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: sage.accentStrong),
              ),
            ),
            Icon(Icons.chevron_right, color: sage.inkLabel),
          ],
        ),
      ),
    );
  }
}
