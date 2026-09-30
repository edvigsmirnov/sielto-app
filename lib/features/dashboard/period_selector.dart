import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/periods/period_service.dart';
import 'package:sielto/features/space/period_ledger.dart';

/// Previous and next period arrows with the cycle's dates. Moves only between
/// existing periods.
class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({this.onJump, this.swipe = true, super.key});

  /// Set by the Feed, which scrolls to the period.
  final void Function(BudgetPeriod period)? onJump;

  /// False at the bottom of the screen, where swipes switch tabs.
  final bool swipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<BudgetPeriod> periods = ref.watch(incomePeriodsProvider);
    final BudgetPeriod? current = ref.watch(selectedPeriodProvider);
    if (current == null || periods.isEmpty) return const SizedBox.shrink();

    final int index = periods.indexWhere(
      (BudgetPeriod p) => p.id == current.id,
    );
    final BudgetPeriod? previous = index > 0 ? periods[index - 1] : null;
    final BudgetPeriod? next = index >= 0 && index < periods.length - 1
        ? periods[index + 1]
        : null;

    final DateLabels dates = DateLabels(context.locale.toString());
    final CalendarDate today = ref.watch(todayProvider);

    // Near the last period, request more.
    final CalendarDate last = periods.last.startDate;
    if (index >= periods.length - 2 &&
        last.isBefore(today.addMonths(PeriodService.maxReachMonths))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(periodReachProvider.notifier)
            .reach(last.addMonths(PeriodService.horizonStepMonths));
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Swipe does what the arrows do.
      onHorizontalDragEnd: !swipe
          ? null
          : (DragEndDetails details) {
              final double? velocity = details.primaryVelocity;
              if (velocity == null ||
                  velocity.abs() < _swipeVelocityThreshold) {
                return;
              }
              final BudgetPeriod? target = velocity > 0 ? previous : next;
              if (target == null) return;
              HapticFeedback.lightImpact();
              _go(ref, target);
            },
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: tr('period.previous'),
            onPressed: previous == null ? null : () => _go(ref, previous),
          ),
          Expanded(
            child: Column(
              // Shrinks to its content as the Feed's bottom bar.
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        _label(current, dates),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    // Window computed without that year's holidays; may still narrow.
                    if (current.holidayDataIncomplete) ...<Widget>[
                      const SizedBox(width: SageSpace.xs),
                      Tooltip(
                        message: tr('holidays.incomplete'),
                        child: Icon(
                          Icons.cloud_off_outlined,
                          size: 16,
                          color: context.sage.inkLabel,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_isCurrent(current, today))
                  Text(
                    tr('period.current'),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: context.sage.accentStrong),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: tr('period.next'),
            onPressed: next == null ? null : () => _go(ref, next),
          ),
        ],
      ),
    );
  }

  static const double _swipeVelocityThreshold = 200;

  void _go(WidgetRef ref, BudgetPeriod period) {
    ref.read(selectedPeriodIdProvider.notifier).select(period.id);
    onJump?.call(period);
  }

  String _label(BudgetPeriod period, DateLabels dates) {
    final CalendarDate? end = period.endDate;
    if (end == null) return dates.dayMonth(period.startDate);
    return '${dates.dayMonth(period.startDate)} — ${dates.dayMonth(end)}';
  }

  bool _isCurrent(BudgetPeriod period, CalendarDate today) {
    if (period.startDate.isAfter(today)) return false;
    final CalendarDate? end = period.endDate;
    return end == null || !end.isBefore(today);
  }
}
