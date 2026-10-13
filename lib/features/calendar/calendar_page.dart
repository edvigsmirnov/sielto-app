import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/layout.dart';
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
import 'package:sielto/features/periods/freeze_providers.dart';
import 'package:sielto/features/shell/app_header.dart';
import 'package:sielto/features/shell/shell_tab.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// Day, Week, Month and Year over one [selectedDateProvider].
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Space space = ref.space;
    final bool wide = ShellLayout.of(context) != ShellMode.phone;
    final CalendarView chosen = ref.watch(calendarViewProvider);
    final CalendarView view = wide && chosen == CalendarView.day
        ? CalendarView.month
        : chosen;
    final CalendarDate selected = ref.watch(selectedDateProvider);
    final CalendarDate today = ref.watch(spaceClockProvider).today();
    final String locale = context.locale.toString();
    final DateLabels dates = DateLabels(locale);
    final MoneyFormat money = MoneyFormat(
      locale: locale,
      currencyCode: space.currencyCode,
    );

    final bool atBottom = controlsAtBottom(
      context,
      ref,
      ControlsScreen.calendar,
    );
    final Widget navigator = _DateNavigator(
      view: view,
      selected: selected,
      today: today,
      dates: dates,
      money: money,
    );
    // Wide enough, one toolbar row: today and the month left, views right.
    final Widget controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) =>
            wide && box.maxWidth >= 860
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _Body.wideWidth),
                  child: Row(
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: () => ref
                            .read(selectedDateProvider.notifier)
                            .select(today),
                        child: Text(tr('feed.today')),
                      ),
                      const SizedBox(width: SageSpace.sm),
                      SizedBox(width: 400, child: navigator),
                      const Spacer(),
                      SizedBox(
                        width: 320,
                        child: _ViewSwitcher(view: view, wide: wide),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ViewSwitcher(view: view, wide: wide),
                  const SizedBox(height: SageSpace.sm),
                  navigator,
                ],
              ),
      ),
    );

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppHeader(title: tr('nav.calendar')),
      floatingActionButton: view == CalendarView.day && !wide
          // Only the Day view has a FAB; other views add through a long press.
          ? FloatingActionButton(
              tooltip: tr('common.add'),
              backgroundColor: context.sage.accent,
              foregroundColor: context.sage.accentOn,
              shape: const CircleBorder(),
              onPressed: () => showDayMenu(context, ref, date: selected),
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
      body: FocusTraversalGroup(
        child: SafeArea(
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
                  child: _Keys(
                    view: view,
                    enabled: wide,
                    child: _Swipe(
                      view: view,
                      enabled: !atBottom && !desktopInput,
                      child: _Body(
                        view: view,
                        selected: selected,
                        today: today,
                        money: money,
                        dates: dates,
                        wide: wide,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
  const _ViewSwitcher({required this.view, required this.wide});

  final CalendarView view;

  /// No Day view: the day has a pane.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SegmentedChoice<CalendarView>(
        values: wide
            ? const <CalendarView>[
                CalendarView.week,
                CalendarView.month,
                CalendarView.year,
              ]
            : CalendarView.values,
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
            child: Container(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: SageSpace.sm,
                vertical: SageSpace.xs,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _label(),
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
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
              ? Builder(
                  builder: (BuildContext button) => IconButton(
                    onPressed: () => showCalendarLegend(
                      button,
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
                  ),
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
    required this.wide,
  });

  final CalendarView view;
  final CalendarDate selected;
  final CalendarDate today;
  final MoneyFormat money;
  final DateLabels dates;
  final bool wide;

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
      if (!wide) ref.read(calendarViewProvider.notifier).open(CalendarView.day);
    }

    void holdDay(CalendarDate date, Offset at) =>
        showDayMenu(context, ref, date: date);

    final Widget grid = view == CalendarView.week
        ? WeekView(
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
          )
        : MonthView(
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
    if (!wide) return grid;
    final Widget pane = _DayPane(
      day: selected,
      today: today,
      money: money,
      dates: dates,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) =>
          box.maxWidth >= _sideBySide
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: SizedBox(
                      height: math.min(box.maxHeight, 620),
                      child: grid,
                    ),
                  ),
                ),
                const SizedBox(width: SageSpace.lg),
                SizedBox(
                  width: 360,
                  height: math.min(box.maxHeight, 620),
                  child: pane,
                ),
              ],
            )
          : _stacked(context, box, grid, pane),
    );
  }

  /// The grid over the day. With large text in a short window there is no
  /// room for both, and they scroll together, the day a full screen tall.
  static Widget _stacked(
    BuildContext context,
    BoxConstraints box,
    Widget grid,
    Widget pane,
  ) {
    final double gridHeight = math.max(
      math.min(box.maxHeight * 0.55, 420),
      MonthView.minHeight(context),
    );
    if (gridHeight + SageSpace.md + _paneMin <= box.maxHeight) {
      return Column(
        children: <Widget>[
          SizedBox(height: gridHeight, child: grid),
          const SizedBox(height: SageSpace.md),
          Expanded(child: pane),
        ],
      );
    }
    return ListView(
      children: <Widget>[
        SizedBox(height: gridHeight, child: grid),
        const SizedBox(height: SageSpace.md),
        SizedBox(height: box.maxHeight, child: pane),
      ],
    );
  }

  static const double _paneMin = 200;

  static const double _sideBySide = 720;

  /// The grid, the gap and the day pane side by side.
  static const double wideWidth = 760 + SageSpace.lg + 360;
}

/// The selected day beside or under the month, with an add button.
class _DayPane extends ConsumerWidget {
  const _DayPane({
    required this.day,
    required this.today,
    required this.money,
    required this.dates,
  });

  final CalendarDate day;
  final CalendarDate today;
  final MoneyFormat money;
  final DateLabels dates;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                dates.weekdayAndDate(day, reference: today),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => showDayMenu(context, ref, date: day),
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('common.add')),
          ),
        ],
      ),
      const SizedBox(height: SageSpace.sm),
      Expanded(
        child: _DayBody(day: day, today: today, money: money),
      ),
    ],
  );
}

/// Desktop keys: arrows move the day, PageUp and PageDown step the view, T
/// goes to today, W, M and Y switch views. The wheel steps the view too.
class _Keys extends ConsumerStatefulWidget {
  const _Keys({required this.view, required this.enabled, required this.child});

  final CalendarView view;
  final bool enabled;
  final Widget child;

  @override
  ConsumerState<_Keys> createState() => _KeysState();
}

class _KeysState extends ConsumerState<_Keys> {
  final FocusNode _focus = FocusNode(
    debugLabel: 'calendar',
    skipTraversal: true,
  );
  DateTime _lastWheel = DateTime(0);

  @override
  void initState() {
    super.initState();
    if (ref.read(shellTabProvider) == ShellTabController.calendar) _claim();
  }

  // Opening the Calendar from the sidebar leaves focus there.
  void _claim() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.enabled) _focus.requestFocus();
  });

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _step(int by) =>
      ref.read(selectedDateProvider.notifier).step(widget.view, by);

  void _move(int days) {
    final SelectedDateController date = ref.read(selectedDateProvider.notifier);
    date.select(ref.read(selectedDateProvider).addDays(days));
  }

  void _show(CalendarView view) =>
      ref.read(calendarViewProvider.notifier).select(view);

  // A trackpad sends a burst per swipe: one step per burst.
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastWheel) < const Duration(milliseconds: 350)) return;
    _lastWheel = now;
    _step(event.scrollDelta.dy > 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    ref.listen(shellTabProvider, (int? _, int tab) {
      if (tab == ShellTabController.calendar) _claim();
    });
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-7),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(7),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.keyT): () => ref
            .read(selectedDateProvider.notifier)
            .select(ref.read(spaceClockProvider).today()),
        const SingleActivator(LogicalKeyboardKey.keyW): () =>
            _show(CalendarView.week),
        const SingleActivator(LogicalKeyboardKey.keyM): () =>
            _show(CalendarView.month),
        const SingleActivator(LogicalKeyboardKey.keyY): () =>
            _show(CalendarView.year),
      },
      child: Focus(
        focusNode: _focus,
        child: Listener(
          onPointerDown: (PointerDownEvent _) => _focus.requestFocus(),
          onPointerSignal: _wheel,
          child: widget.child,
        ),
      ),
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
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
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
      onHoldRecord: (FeedRecord r) => showRecordMenu(context, ref, record: r),
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
