import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// The four scales of the Calendar screen (spec 8.1).
enum CalendarView { day, week, month, year }

/// The date every view is built around.
///
/// One state for all four scales, and it survives a scale change: a Day on the
/// 15th becomes the week containing the 15th, then August, then 2026. That
/// shared date is what makes the scales feel like one screen rather than four
/// (spec 8.1).
class SelectedDateController extends Notifier<CalendarDate> {
  @override
  CalendarDate build() => ref.watch(spaceClockProvider).today();

  void select(CalendarDate date) => state = date;

  /// Moves by whole units of [view] — a day, a week, a month, a year.
  ///
  /// Month and year steps keep the day-of-month where they can: [addMonths]
  /// clamps, so browsing from 31 March to February and back lands on the 28th
  /// rather than overflowing into March.
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

/// Which scale is showing. Not persisted: the screen opens on the Month, which
/// is the scale that answers "what does this month look like".
final NotifierProvider<CalendarViewController, CalendarView>
calendarViewProvider = NotifierProvider<CalendarViewController, CalendarView>(
  CalendarViewController.new,
);

class CalendarViewController extends Notifier<CalendarView> {
  @override
  CalendarView build() => CalendarView.month;

  void select(CalendarView view) => state = view;
}

/// The days one view covers, inclusive.
///
/// The Month range runs over the whole six-week grid rather than the calendar
/// month, because the grid draws the neighbouring days and they carry figures
/// too.
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

/// Six weeks, always.
///
/// A grid that grows to five rows in one month and six in the next moves every
/// cell under the finger when the arrows are used. Fixed height costs one
/// mostly-empty row and buys a still layout.
const int monthGridDays = 42;
