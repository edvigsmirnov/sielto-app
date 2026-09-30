import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_data.dart';
import 'package:sielto/features/calendar/calendar_legend.dart';
import 'package:sielto/features/calendar/calendar_menu.dart';
import 'package:sielto/features/calendar/calendar_picker.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/day_marks.dart';
import 'package:sielto/features/calendar/day_view.dart';
import 'package:sielto/features/calendar/month_view.dart';
import 'package:sielto/features/calendar/week_categories.dart';
import 'package:sielto/features/calendar/week_view.dart';
import 'package:sielto/features/calendar/year_view.dart';
import 'package:sielto/features/feed/feed_menu.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/feed/record_actions.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/periods/freeze_providers.dart';
import 'package:sielto/features/shell/app_header.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Day, Week, Month and Year over one [selectedDateProvider].
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Space space = ref.space;
    final CalendarView view = ref.watch(calendarViewProvider);
    final CalendarDate selected = ref.watch(selectedDateProvider);
    final CalendarDate today = ref.watch(spaceClockProvider).today();
    final String locale = context.locale.toString();
    final DateLabels dates = DateLabels(locale);
    final MoneyFormat money = MoneyFormat(
      locale: locale,
      currencyCode: space.currencyCode,
    );

    final bool atBottom = ref
        .watch(controlsAtBottomProvider)
        .contains(ControlsScreen.calendar);
    final Widget controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ViewSwitcher(view: view),
          const SizedBox(height: SageSpace.sm),
          _DateNavigator(
            view: view,
            selected: selected,
            today: today,
            dates: dates,
            money: money,
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppHeader(title: tr('nav.calendar')),
      floatingActionButton: view == CalendarView.day
          // Only the Day view has a FAB; other views add through a long press.
          ? FloatingActionButton(
              backgroundColor: context.sage.accent,
              foregroundColor: context.sage.accentOn,
              shape: const CircleBorder(),
              onPressed: () => openPaymentForm(context, date: selected),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: atBottom
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(top: SageSpace.sm),
                child: controls,
              ),
            )
          : null,
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            if (!atBottom) ...<Widget>[
              controls,
              const SizedBox(height: SageSpace.sm),
            ],
            // No freeze banner: the Calendar is not bound to one period.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SageSpace.gutter,
                ),
                child: _Swipe(
                  view: view,
                  enabled: !atBottom,
                  child: _Body(
                    view: view,
                    selected: selected,
                    today: today,
                    money: money,
                    dates: dates,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal swipe steps the view, like the arrows. Off in the Day view and
/// with the controls at the bottom.
class _Swipe extends ConsumerWidget {
  const _Swipe({
    required this.view,
    required this.enabled,
    required this.child,
  });

  final CalendarView view;
  final bool enabled;
  final Widget child;

  static const double _velocityThreshold = 200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view == CalendarView.day || !enabled) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (DragEndDetails details) {
        final double? velocity = details.primaryVelocity;
        if (velocity == null || velocity.abs() < _velocityThreshold) return;
        HapticFeedback.lightImpact();
        ref
            .read(selectedDateProvider.notifier)
            .step(view, velocity > 0 ? -1 : 1);
      },
      child: child,
    );
  }
}

class _ViewSwitcher extends ConsumerWidget {
  const _ViewSwitcher({required this.view});

  final CalendarView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SegmentedChoice<CalendarView>(
        values: CalendarView.values,
        selected: view,
        labelOf: (CalendarView v) => tr('calendar.view.${v.name}'),
        onChanged: (CalendarView v) =>
            ref.read(calendarViewProvider.notifier).select(v),
      );
}

/// Arrows step the view; tapping the label opens a picker.
class _DateNavigator extends ConsumerWidget {
  const _DateNavigator({
    required this.view,
    required this.selected,
    required this.today,
    required this.dates,
    required this.money,
  });

  final CalendarView view;
  final CalendarDate selected;
  final CalendarDate today;
  final DateLabels dates;
  final MoneyFormat money;

  /// Fixed width, so the label does not shift when an arrow hides.
  static const double _slot = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final CalendarViewController scales = ref.read(
      calendarViewProvider.notifier,
    );
    void step(int by) => ref.read(selectedDateProvider.notifier).step(view, by);

    return Row(
      children: <Widget>[
        SizedBox(
          width: _slot,
          child: scales.canGoBack()
              ? IconButton(
                  onPressed: scales.back,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: tr('calendar.back'),
                )
              : null,
        ),
        IconButton(
          onPressed: () => step(-1),
          icon: const Icon(Icons.chevron_left),
          color: sage.accentStrong,
          tooltip: tr('calendar.previous'),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _pick(context, ref),
            borderRadius: BorderRadius.circular(SageRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SageSpace.sm,
                vertical: SageSpace.xs,
              ),
              child: Text(
                _label(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => step(1),
          icon: const Icon(Icons.chevron_right),
          color: sage.accentStrong,
          tooltip: tr('calendar.next'),
        ),
        SizedBox(
          width: _slot,
          child: view == CalendarView.month || view == CalendarView.week
              ? IconButton(
                  onPressed: () => showCalendarLegend(
                    context,
                    mode: ref.read(currentSpaceProvider)!.budgetMode,
                    money: money,
                    loadThreshold: ref
                        .read(dayMarksProvider(view))
                        .value
                        ?.threshold,
                  ),
                  icon: const Icon(Icons.info_outline),
                  color: sage.inkLabel,
                  tooltip: tr('calendar.legend.title'),
                )
              : null,
        ),
      ],
    );
  }

  String _label() {
    final ({CalendarDate from, CalendarDate to}) range = rangeOf(
      view,
      selected,
    );
    return switch (view) {
      CalendarView.day => dates.weekdayAndDate(selected, reference: today),
      CalendarView.week => dates.range(range.from, range.to, reference: today),
      CalendarView.month => dates.monthYear(selected),
      CalendarView.year => selected.year.toString(),
    };
  }

  /// Jumps at the grain of the current view.
  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final CalendarDate? picked = await pickCalendarDate(
      context,
      view: view,
      selected: selected,
      today: today,
    );
    if (picked == null) return;
    ref.read(selectedDateProvider.notifier).select(picked);
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.view,
    required this.selected,
    required this.today,
    required this.money,
    required this.dates,
  });

  final CalendarView view;
  final CalendarDate selected;
  final CalendarDate today;
  final MoneyFormat money;
  final DateLabels dates;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _StepSlide(
    view: view,
    anchor: rangeOf(view, selected).from,
    child: _content(context, ref),
  );

  Widget _content(BuildContext context, WidgetRef ref) {
    if (view == CalendarView.day) {
      return _DayBody(day: selected, today: today, money: money);
    }
    if (view == CalendarView.year) {
      final Map<CalendarDate, DayTotals> totals =
          ref.watch(monthlyTotalsProvider).value ??
          const <CalendarDate, DayTotals>{};
      return YearView(
        year: selected.year,
        totals: totals,
        today: today,
        selected: selected,
        money: money,
        dates: dates,
        onOpenMonth: (CalendarDate month) {
          ref.read(selectedDateProvider.notifier).select(month);
          ref.read(calendarViewProvider.notifier).open(CalendarView.month);
        },
      );
    }

    final Map<CalendarDate, DayTotals> totals =
        ref.watch(dailyTotalsProvider(view)).value ??
        const <CalendarDate, DayTotals>{};
    final DayMarks marks =
        ref.watch(dayMarksProvider(view)).value ?? DayMarks.empty;

    void openDay(CalendarDate date) {
      ref.read(selectedDateProvider.notifier).select(date);
      ref.read(calendarViewProvider.notifier).open(CalendarView.day);
    }

    void holdDay(CalendarDate date, Offset at) =>
        showDayMenu(context, ref, date: date, at: at);

    if (view == CalendarView.week) {
      return WeekView(
        week: selected.startOfWeek,
        selected: selected,
        totals: totals,
        marks: marks,
        categories:
            ref.watch(weekCategoryNamesProvider).value ??
            const <CalendarDate, List<String>>{},
        today: today,
        money: money,
        dates: dates,
        onOpenDay: openDay,
        onHoldDay: holdDay,
      );
    }

    return MonthView(
      month: selected,
      selected: selected,
      totals: totals,
      marks: marks,
      today: today,
      money: money,
      dates: dates,
      onOpenDay: openDay,
      onHoldDay: holdDay,
    );
  }
}

/// Slides the view sideways on a step, in the direction of travel; fades on a
/// change of view. Wraps the views so the outgoing one keeps its own data.
class _StepSlide extends StatefulWidget {
  const _StepSlide({
    required this.view,
    required this.anchor,
    required this.child,
  });

  final CalendarView view;

  /// First day of the range on screen.
  final CalendarDate anchor;
  final Widget child;

  @override
  State<_StepSlide> createState() => _StepSlideState();
}

class _StepSlideState extends State<_StepSlide> {
  /// 1 forward, -1 back, 0 for a change of view.
  int _direction = 0;

  @override
  void didUpdateWidget(_StepSlide old) {
    super.didUpdateWidget(old);
    if (widget.view != old.view) {
      _direction = 0;
    } else if (widget.anchor != old.anchor) {
      _direction = widget.anchor.isAfter(old.anchor) ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Key current = ValueKey<String>(
      '${widget.view.name}:${widget.anchor.toIso()}',
    );
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (Widget? child, List<Widget> previous) => Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[...previous, ?child],
        ),
        // Rebuilt each time, so the outgoing child also uses the latest direction.
        transitionBuilder: (Widget child, Animation<double> animation) {
          if (_direction == 0) {
            return FadeTransition(opacity: animation, child: child);
          }
          final double side = child.key == current
              ? _direction.toDouble()
              : -_direction.toDouble();
          return SlideTransition(
            position: Tween<Offset>(
              begin: Offset(side, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        child: KeyedSubtree(key: current, child: widget.child),
      ),
    );
  }
}

/// Day view actions; same behaviour as the Feed.
class _DayBody extends ConsumerWidget {
  const _DayBody({required this.day, required this.today, required this.money});

  final CalendarDate day;
  final CalendarDate today;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DayRecords? records = ref.watch(dayRecordsProvider(day));
    if (records == null) {
      return const Center(child: LeafLoader());
    }

    return DayView(
      day: day,
      records: records,
      orderMode: ref.watch(currentSpaceProvider)!.feedOrderMode,
      today: today,
      categories:
          ref.watch(categoryIndexProvider).value ?? const <String, Category>{},
      density: ref.watch(feedDensityProvider),
      money: money,
      isFrozen: ref.watch(freezeLookupProvider).isFrozen,
      dayOff: ref.watch(dayOffNamesProvider(day)),
      deadline: _deadlineOn(
        day,
        ref.watch(spacePeriodsProvider).value ?? const <BudgetPeriod>[],
      ),
      onEdit: (FeedRecord r) => editRecord(context, r),
      onTogglePaid: (FeedRecord r) => togglePaid(context, ref, r),
      onDelete: (FeedRecord r) => deleteRecord(context, ref, r),
      onHoldRecord: (FeedRecord r) =>
          showRecordMenu(context, ref, record: r, today: today),
    );
  }
}

DeadlineKind? _deadlineOn(CalendarDate day, List<BudgetPeriod> periods) {
  for (final BudgetPeriod p in periods) {
    if (p.deadlineDate == day) {
      return p.deadlineIsHard ? DeadlineKind.hard : DeadlineKind.soft;
    }
  }
  return null;
}
