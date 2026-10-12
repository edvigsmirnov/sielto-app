import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/action_sheet.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/analytics/analytics_data.dart';
import 'package:sielto/features/analytics/analytics_range.dart';
import 'package:sielto/features/analytics/range_dialog.dart';
import 'package:sielto/features/space/period_ledger.dart';

/// Blocks shared by the Analytics levels.

/// Range with arrows and a unit picker. Shown on every level: Analytics uses
/// calendar ranges, the Dashboard uses income cycles.
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
          onPressed: () => stepAnalyticsRange(ref, -1),
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
          onPressed: () => stepAnalyticsRange(ref, 1),
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
    final bool periods = ref.read(incomePeriodsProvider).isNotEmpty;
    final RangeUnit? picked = await showActionSheet<RangeUnit>(
      context,
      title: tr('analytics.unit.title'),
      groups: <List<SheetAction<RangeUnit>>>[
        <SheetAction<RangeUnit>>[
          for (final RangeUnit unit in RangeUnit.values)
            if (unit != RangeUnit.period || periods)
              SheetAction<RangeUnit>(
                unit == range.unit ? Icons.check : _iconOf(unit),
                tr('analytics.unit.${unit.name}'),
                unit,
              ),
        ],
      ],
    );
    if (picked == null || !context.mounted) return;
    if (picked != RangeUnit.custom) {
      setAnalyticsUnit(ref, picked);
      return;
    }
    final (CalendarDate, CalendarDate)? dates = await askDateRange(
      context,
      from: range.from,
      to: range.to,
    );
    if (dates == null) return;
    ref
        .read(analyticsChoiceProvider.notifier)
        .choose(AnalyticsRange.between(RangeUnit.custom, dates.$1, dates.$2));
  }

  static IconData _iconOf(RangeUnit unit) => switch (unit) {
    RangeUnit.period => Icons.payments_outlined,
    RangeUnit.custom => Icons.date_range_outlined,
    _ => Icons.calendar_month_outlined,
  };
}

/// Full span for a quarter; the month or year alone otherwise.
String rangeLabel(AnalyticsRange range, String locale) {
  final DateLabels dates = DateLabels(locale);
  return switch (range.unit) {
    RangeUnit.month => dates.monthYear(range.anchor),
    RangeUnit.quarter ||
    RangeUnit.period ||
    RangeUnit.custom => dates.range(range.from, range.to),
    RangeUnit.year => range.anchor.year.toString(),
  };
}

/// Everything, mandatory or variable.
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

/// Range caption for levels without a picker.
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

/// Label and figure on a hairlined row.
class SliceRow extends StatelessWidget {
  const SliceRow({
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;

  /// Null for a row that leads nowhere.
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

/// Right swipe pops the level; a hint at the foot says so.
class SwipeBack extends StatelessWidget {
  const SwipeBack({required this.child, super.key});

  final Widget child;

  static const double _velocityThreshold = 200;

  @override
  Widget build(BuildContext context) {
    if (desktopInput) return child;
    final SageColors sage = context.sage;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (DragEndDetails details) {
        final double? velocity = details.primaryVelocity;
        if (velocity != null && velocity > _velocityThreshold) {
          HapticFeedback.lightImpact();
          Navigator.of(context).maybePop();
        }
      },
      child: Column(
        children: <Widget>[
          Expanded(child: child),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SageSpace.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.swipe_right_outlined,
                    size: 16,
                    color: sage.inkLabel,
                  ),
                  const SizedBox(width: SageSpace.xs),
                  Flexible(
                    child: Text(
                      tr('analytics.swipeBack'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: sage.inkLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
