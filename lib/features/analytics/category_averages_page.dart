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

/// Analytics level 3: the same titles read as averages (spec 8.2).
///
/// The point of the level is planning, not accounting: what a typical bill from
/// this payee comes to, so the next one can be entered with a figure rather
/// than a guess.
class CategoryAveragesPage extends ConsumerWidget {
  const CategoryAveragesPage({
    required this.categoryKey,
    required this.title,
    super.key,
  });

  final String categoryKey;

  /// The category's name. The header reads `Averages — <name>`.
  final String title;

  static Future<void> open(
    BuildContext context, {
    required String categoryKey,
    required String title,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext _) =>
          CategoryAveragesPage(categoryKey: categoryKey, title: title),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Space space = ref.space;
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final MoneyFormat money = MoneyFormat(
      locale: context.locale.toString(),
      currencyCode: space.currencyCode,
    );
    final List<AnalyticsSlice> slices =
        ref.watch(titleTotalsProvider(categoryKey)).value ??
        const <AnalyticsSlice>[];

    // The mean payment across the category, not the mean of the means: a payee
    // billed once must not weigh as much as one billed thirty times.
    final int count = slices.fold(
      0,
      (int sum, AnalyticsSlice s) => sum + s.count,
    );
    final Decimal total = slices.fold(
      Decimal.zero,
      (Decimal sum, AnalyticsSlice s) => sum + s.total,
    );
    final Decimal average = count == 0
        ? Decimal.zero
        : (total / Decimal.fromInt(count)).toDecimal(
            scaleOnInfinitePrecision: 2,
          );

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: AppBar(
        backgroundColor: sage.surface,
        title: Text(
          tr(
            'analytics.averagesTitle',
            namedArgs: <String, String>{'category': title},
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
          children: <Widget>[
            const RangeCaption(),
            const SizedBox(height: SageSpace.md),
            if (slices.isEmpty)
              EmptyState(message: tr('analytics.empty'))
            else ...<Widget>[
              SageCard(
                color: sage.accentTint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      tr('analytics.averageTicket'),
                      style: text.bodySmall?.copyWith(color: sage.accentStrong),
                    ),
                    const SizedBox(height: SageSpace.xs),
                    Text(money.format(average), style: text.titleLarge),
                  ],
                ),
              ),
              const SizedBox(height: SageSpace.md),
              for (final AnalyticsSlice slice in slices)
                SliceRow(
                  label: slice.label,
                  // The mean sign, so the figure is not mistaken for a total
                  // on a screen where both shapes appear.
                  value: '⌀ ${money.format(slice.average)}',
                ),
              const SizedBox(height: SageSpace.md),
              Text(
                tr('analytics.averagesHint'),
                style: text.bodySmall?.copyWith(color: sage.inkLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
