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
import 'package:sielto/features/analytics/category_breakdown_page.dart';
import 'package:sielto/features/analytics/donut_chart.dart';
import 'package:sielto/features/categories/category_colors.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Analytics level 1: the top categories of a calendar range (spec 8.2).
///
/// Opened from the Dashboard and closed back to it, which is why the header
/// carries a cross rather than a back arrow and why this is not a fourth tab:
/// the bottom bar stays on the three screens throughout (design section 11).
class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  /// Pushes the analytics stack over whatever is on screen.
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (BuildContext _) => const AnalyticsPage()),
  );

  /// Wedges beyond this go into one "everything else" slice: a ring of
  /// eighteen hairline wedges says less than four and a remainder.
  static const int _wedges = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Space space = ref.space;
    final String locale = context.locale.toString();
    final MoneyFormat money = MoneyFormat(
      locale: locale,
      currencyCode: space.currencyCode,
    );
    final Map<String, Category> categories =
        ref.watch(categoryIndexProvider).value ?? const <String, Category>{};
    final List<AnalyticsSlice> slices =
        ref.watch(categoryTotalsProvider).value ?? const <AnalyticsSlice>[];

    final Decimal total = slices.fold(
      Decimal.zero,
      (Decimal sum, AnalyticsSlice s) => sum + s.total,
    );

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(
        backgroundColor: context.sage.surface,
        title: Text(tr('analytics.title')),
        actions: <Widget>[
          IconButton(
            // The cross, not a back arrow: level 1 closes the whole stack and
            // returns to the Dashboard it was opened from.
            icon: const Icon(Icons.close),
            tooltip: tr('common.close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
          children: <Widget>[
            const RangeHeader(),
            const SizedBox(height: SageSpace.md),
            const ExpenseTypeFilter(),
            const SizedBox(height: SageSpace.lg),
            if (slices.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: SageSpace.xl),
                child: EmptyState(message: tr('analytics.empty')),
              )
            else ...<Widget>[
              _Summary(
                slices: slices,
                total: total,
                categories: categories,
                money: money,
              ),
              const SizedBox(height: SageSpace.lg),
              for (final AnalyticsSlice slice in slices)
                _CategoryRow(
                  slice: slice,
                  category: categories[slice.key],
                  money: money,
                  onTap: () => CategoryBreakdownPage.open(
                    context,
                    categoryKey: slice.key,
                    title: _labelOf(slice, categories),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// A category that was deleted keeps its name on the payments filed under it
  /// (spec 7); one that never existed is the uncategorised slice.
  static String _labelOf(
    AnalyticsSlice slice,
    Map<String, Category> categories,
  ) => categories[slice.key]?.title ?? tr('category.none');

  /// The ring and its legend, as one block.
  static List<DonutSlice> wedges(
    List<AnalyticsSlice> slices,
    Decimal total,
    Map<String, Category> categories,
    SageColors sage,
  ) {
    if (total == Decimal.zero) return const <DonutSlice>[];
    double fraction(Decimal part) => (part / total).toDouble();

    final List<DonutSlice> out = <DonutSlice>[
      for (final AnalyticsSlice s in slices.take(_wedges))
        DonutSlice(
          fraction: fraction(s.total),
          // The users' own colour where the category has one; the neutral
          // marker token where it does not.
          color: parseCategoryColor(categories[s.key]?.color) ?? sage.sand,
        ),
    ];
    if (slices.length > _wedges) {
      final Decimal rest = slices
          .skip(_wedges)
          .fold(Decimal.zero, (Decimal sum, AnalyticsSlice s) => sum + s.total);
      out.add(DonutSlice(fraction: fraction(rest), color: sage.hairline));
    }
    return out;
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.slices,
    required this.total,
    required this.categories,
    required this.money,
  });

  final List<AnalyticsSlice> slices;
  final Decimal total;
  final Map<String, Category> categories;
  final MoneyFormat money;

  /// Legend entries. Beyond three the list under the ring becomes the thing
  /// being read, and the full list is right below it anyway.
  static const int _legend = 3;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Row(
      children: <Widget>[
        DonutChart(
          slices: AnalyticsPage.wedges(slices, total, categories, sage),
          centre: money.short(total),
          caption: tr('analytics.inRange'),
        ),
        const SizedBox(width: SageSpace.md),
        Expanded(
          child: Column(
            children: <Widget>[
              for (final AnalyticsSlice slice in slices.take(_legend))
                _LegendLine(
                  color:
                      parseCategoryColor(categories[slice.key]?.color) ??
                      sage.sand,
                  label: categories[slice.key]?.title ?? tr('category.none'),
                  amount: money.short(slice.total),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({
    required this.color,
    required this.label,
    required this.amount,
  });

  final Color color;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: SageSpace.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: context.sage.ink),
            ),
          ),
          const SizedBox(width: SageSpace.sm),
          Text(amount, maxLines: 1, style: text.labelMedium),
        ],
      ),
    );
  }
}

/// One category, its record count, its total, and the way into level 2.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.slice,
    required this.category,
    required this.money,
    required this.onTap,
  });

  final AnalyticsSlice slice;
  final Category? category;
  final MoneyFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
            child: Row(
              children: <Widget>[
                CategoryMark(
                  color: category?.color,
                  icon: category?.icon,
                  size: 30,
                ),
                const SizedBox(width: SageSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        category?.title ?? tr('category.none'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge,
                      ),
                      Text(
                        plural('analytics.records', slice.count),
                        style: text.bodySmall?.copyWith(color: sage.inkLabel),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SageSpace.sm),
                Text(
                  money.format(slice.total),
                  style: text.titleSmall?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: sage.inkLabel),
              ],
            ),
          ),
        ),
        const Hairline(),
      ],
    );
  }
}
