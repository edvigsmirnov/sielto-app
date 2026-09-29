import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/domain/value/calendar_date.dart';

enum CalendarView { day, week, month, year }

/// The date every view is built around. Kept across view changes.
class SelectedDateController extends Notifier<CalendarDate> {
  @override
  CalendarDate build() => ref.watch(spaceClockProvider).today();

  void select(CalendarDate date) => state = date;

  /// Moves by whole [view] units. [addMonths] clamps the day.
  void step(CalendarView view, int by) => state = switch (view) {
    CalendarView.day => state.addDays(by),
    CalendarView.week => state.addDays(by * 7),
    CalendarView.month => state.addMonths(by),
    CalendarView.year => state.addMonths(by * 12),
  };
}

final NotifierProvider<SelectedDateController, CalendarDate>
selectedDateProvider = NotifierProvider<SelectedDateController, CalendarDate>(
  SelectedDateController.new,
);

/// Not persisted; opens on Month.
final NotifierProvider<CalendarViewController, CalendarView>
calendarViewProvider = NotifierProvider<CalendarViewController, CalendarView>(
  CalendarViewController.new,
);

class CalendarViewController extends Notifier<CalendarView> {
  /// Views zoomed in from, for Back.
  final List<CalendarView> _trail = <CalendarView>[];

  @override
  CalendarView build() {
    _trail.clear();
    return CalendarView.month;
  }

  /// From the switcher: clears the trail.
  void select(CalendarView view) {
    _trail.clear();
    state = view;
  }

  /// From a tap into a day or month: Back returns here.
  void open(CalendarView view) {
    _trail.add(state);
    state = view;
  }

  bool canGoBack() => _trail.isNotEmpty;

  /// False when there is nothing to return to.
  bool back() {
    if (_trail.isEmpty) return false;
    state = _trail.removeLast();
    return true;
  }
}

/// Inclusive. Month covers the whole six-week grid.
({CalendarDate from, CalendarDate to}) rangeOf(
  CalendarView view,
  CalendarDate around,
) => switch (view) {
  CalendarView.day => (from: around, to: around),
  CalendarView.week => (
    from: around.startOfWeek,
    to: around.startOfWeek.addDays(6),
  ),
  CalendarView.month => (
    from: around.firstOfMonth.startOfWeek,
    to: around.firstOfMonth.startOfWeek.addDays(monthGridDays - 1),
  ),
  CalendarView.year => (
    from: CalendarDate(around.year, 1, 1),
    to: CalendarDate(around.year, 12, 31),
  ),
};

/// Six weeks, so the grid never changes height.
const int monthGridDays = 42;
