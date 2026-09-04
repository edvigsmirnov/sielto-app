import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/analytics/analytics_data.dart';
import 'package:sielto/features/analytics/analytics_range.dart';

/// The blocks the three Analytics levels share.

/// The range, with arrows and a unit picker (spec 8.2).
///
/// Mandatory on every level, not decoration (plan G9): Analytics counts
/// calendar ranges while the Dashboard counts income cycles, so the same-looking
/// month legitimately gives two different totals and the screen has to say
/// which one it is showing.
class RangeHeader extends ConsumerWidget {
  const RangeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AnalyticsRange range = ref.watch(analyticsRangeProvider);
    final SageColors sage = context.sage;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          onPressed: () => ref.read(analyticsRangeProvider.notifier).step(-1),
          icon: const Icon(Icons.chevron_left),
          color: sage.accentStrong,
          tooltip: tr('calendar.previous'),
        ),
        Flexible(
          child: InkWell(
            onTap: () => _pickUnit(context, ref, range),
            borderRadius: BorderRadius.circular(SageRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SageSpace.sm,
                vertical: SageSpace.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      rangeLabel(range, context.locale.toString()),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(width: SageSpace.xs),
                  Icon(Icons.expand_more, size: 16, color: sage.inkLabel),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => ref.read(analyticsRangeProvider.notifier).step(1),
          icon: const Icon(Icons.chevron_right),
          color: sage.accentStrong,
          tooltip: tr('calendar.next'),
        ),
      ],
    );
  }

  Future<void> _pickUnit(
    BuildContext context,
    WidgetRef ref,
    AnalyticsRange range,
  ) async {
    final RangeUnit? picked = await showModalBottomSheet<RangeUnit>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final RangeUnit unit in RangeUnit.values)
              ListTile(
                title: Text(tr('analytics.unit.${unit.name}')),
                trailing: unit == range.unit
                    ? Icon(Icons.check, color: context.sage.accentStrong)
                    : null,
                onTap: () => Navigator.of(sheet).pop(unit),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    ref.read(analyticsRangeProvider.notifier).setUnit(picked);
  }
}

/// The range as words. The full span for a quarter, the month or the year
/// alone otherwise — a month printed as two dates says the same thing twice.
String rangeLabel(AnalyticsRange range, String locale) {
  final DateLabels dates = DateLabels(locale);
  return switch (range.unit) {
    RangeUnit.month => dates.monthYear(range.anchor),
    RangeUnit.quarter => dates.range(range.from, range.to),
    RangeUnit.year => range.anchor.year.toString(),
  };
}

/// Everything / mandatory / variable (spec 8.2).
///
/// The second cut through the same range: what is fixed against where the
/// budget is still flexible.
class ExpenseTypeFilter extends ConsumerWidget {
  const ExpenseTypeFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExpenseType? selected = ref.watch(expenseTypeFilterProvider);
    return SegmentedChoice<ExpenseType?>(
      values: const <ExpenseType?>[
        null,
        ExpenseType.mandatory,
        ExpenseType.variable,
      ],
      selected: selected,
      labelOf: (ExpenseType? t) => tr(expenseTypeKey(t)),
      onChanged: (ExpenseType? t) =>
          ref.read(expenseTypeFilterProvider.notifier).select(t),
    );
  }
}

/// The range as a caption, for the levels that have no picker of their own.
class RangeCaption extends ConsumerWidget {
  const RangeCaption({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Text(
      rangeLabel(ref.watch(analyticsRangeProvider), context.locale.toString()),
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

/// A label and its figure on one hairlined row: the shape levels 2 and 3 are
/// both lists of.
class SliceRow extends StatelessWidget {
  const SliceRow({
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;

  /// Null where the row is a figure rather than a way further down.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: SageSpace.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyLarge,
            ),
          ),
          const SizedBox(width: SageSpace.sm),
          Text(
            value,
            style: text.labelLarge?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: context.sage.inkLabel),
        ],
      ),
    );

    return Column(
      children: <Widget>[
        if (onTap == null) row else InkWell(onTap: onTap, child: row),
        const Hairline(),
      ],
    );
  }
}
