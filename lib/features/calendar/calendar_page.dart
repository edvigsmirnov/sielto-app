import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/calendar_repository.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/calendar/calendar_data.dart';
import 'package:sielto/features/calendar/calendar_menu.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/calendar/day_marks.dart';
import 'package:sielto/features/calendar/day_view.dart';
import 'package:sielto/features/calendar/month_view.dart';
import 'package:sielto/features/calendar/week_categories.dart';
import 'package:sielto/features/calendar/week_view.dart';
import 'package:sielto/features/calendar/year_view.dart';
import 'package:sielto/features/feed/feed_menu.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/incomes/income_form_page.dart';
import 'package:sielto/features/incomes/receipt_dialog.dart';
import 'package:sielto/features/payments/payment_form_page.dart';
import 'package:sielto/features/periods/freeze_providers.dart';
import 'package:sielto/features/periods/freeze_ui.dart' show guardFreeze;
import 'package:sielto/features/shell/app_header.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// The Calendar screen: Day / Week / Month / Year over one shared date
/// (spec 8.1).
///
/// A real calendar rather than a helper widget. The four scales are one screen
/// because they share [selectedDateProvider]: switching scale reframes the
/// same date instead of starting over, which is what makes the switcher feel
/// like a zoom.
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

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppHeader(title: tr('nav.calendar')),
      floatingActionButton: view == CalendarView.day
          // Only the Day view has one date to add to. Elsewhere the entry point
          // is a long press on the day itself (spec 8.1).
          ? FloatingActionButton(
              backgroundColor: context.sage.accent,
              foregroundColor: context.sage.accentOn,
              shape: const CircleBorder(),
              onPressed: () => openPaymentForm(context, date: selected),
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
          child: Column(
            children: <Widget>[
              _ViewSwitcher(view: view),
              const SizedBox(height: SageSpace.sm),
              _DateNavigator(
                view: view,
                selected: selected,
                today: today,
                dates: dates,
              ),
              const SizedBox(height: SageSpace.sm),
              // No freeze banner. The banner speaks for one period and the
              // Calendar is not bound to one; a frozen record still says so
              // itself in the Day view (spec 5.5).
              Expanded(
                child: _Body(
                  view: view,
                  selected: selected,
                  today: today,
                  money: money,
                  dates: dates,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Day / Week / Month / Year. The scale, never the date.
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

/// Arrows either side of the label, and a tap on the label opens a picker
/// (spec 8.1).
///
/// One control for all four scales, because the arrows mean the same thing
/// everywhere — one step of whatever is on screen.
class _DateNavigator extends ConsumerWidget {
  const _DateNavigator({
    required this.view,
    required this.selected,
    required this.today,
    required this.dates,
  });

  final CalendarView view;
  final CalendarDate selected;
  final CalendarDate today;
  final DateLabels dates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    void step(int by) => ref.read(selectedDateProvider.notifier).step(view, by);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          onPressed: () => step(-1),
          icon: const Icon(Icons.chevron_left),
          color: sage.accentStrong,
          tooltip: tr('calendar.previous'),
        ),
        Flexible(
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

  /// The picker jumps rather than steps. Year and Month get a whole calendar
  /// too: landing on the right day is harmless, since the scale on screen is
  /// what decides how the date is read.
  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selected.toUtcMidnight(),
      firstDate: DateTime.utc(today.year - 10),
      lastDate: DateTime.utc(today.year + 10),
    );
    if (picked == null) return;
    ref
        .read(selectedDateProvider.notifier)
        .select(CalendarDate.fromDateTime(picked));
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
  Widget build(BuildContext context, WidgetRef ref) {
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
          ref.read(calendarViewProvider.notifier).select(CalendarView.month);
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
      ref.read(calendarViewProvider.notifier).select(CalendarView.day);
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

/// The Day view and the four things a row can do there.
///
/// The handlers mirror the Feed's exactly — including the confirmations and the
/// freeze guard — because the record is the same record; only the list around
/// it differs.
class _DayBody extends ConsumerWidget {
  const _DayBody({required this.day, required this.today, required this.money});

  final CalendarDate day;
  final CalendarDate today;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DayRecords? records = ref.watch(dayRecordsProvider(day));
    if (records == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return DayView(
      day: day,
      records: records,
      today: today,
      categories:
          ref.watch(categoryIndexProvider).value ?? const <String, Category>{},
      density: ref.watch(feedDensityProvider),
      money: money,
      isFrozen: ref.watch(freezeLookupProvider).isFrozen,
      onEdit: (FeedRecord r) => _edit(context, r),
      onTogglePaid: (FeedRecord r) => _togglePaid(context, ref, r),
      onDelete: (FeedRecord r) => _delete(context, ref, r),
      onHoldRecord: (FeedRecord r) =>
          showRecordMenu(context, ref, record: r, today: today),
    );
  }

  void _edit(BuildContext context, FeedRecord record) {
    if (record.isIncome) {
      openIncomeForm(context, incomeId: record.id, date: record.date);
      return;
    }
    openPaymentForm(context, paymentId: record.id, date: record.date);
  }

  /// Marking something paid never asks; clearing the mark on a mandatory
  /// payment does (spec 4.5).
  Future<void> _togglePaid(
    BuildContext context,
    WidgetRef ref,
    FeedRecord record,
  ) async {
    final Repositories repos = ref.read(repositoriesProvider);
    final bool next = !record.isPaid;

    if (!next && record.isMandatory && !await confirmMandatory(context)) {
      return;
    }
    if (!context.mounted) return;

    if (!record.isIncome) {
      await guardFreeze(
        context,
        () => repos.payments.setPaid(record.id, isPaid: next),
      );
      return;
    }

    if (next && record.amount == null) {
      // The figure has to exist before a receipt can be confirmed, or the
      // period's arithmetic stays uncomputable (spec 4.5).
      openIncomeForm(context, incomeId: record.id, date: record.date);
      return;
    }

    CalendarDate? actual;
    if (next) {
      actual = await askReceiptDate(context, expected: record.date);
      if (actual == null || !context.mounted) return;
    }

    await guardFreeze(
      context,
      () => repos.incomes.update(
        record.id,
        isPaid: Value<bool>(next),
        // Clearing the receipt clears the fact with it (spec 5.4).
        actualDate: Value<CalendarDate?>(actual),
      ),
    );
    // An anchor arriving early moves the cycle it opens (spec 5.4).
    ref.invalidate(periodRefreshProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    FeedRecord record,
  ) async {
    if (record.isMandatory && !await confirmMandatory(context)) return;
    if (!context.mounted) return;
    final Repositories repos = ref.read(repositoriesProvider);

    final bool deleted = await guardFreeze(
      context,
      () => record.isIncome
          ? repos.incomes.softDelete(record.id)
          : repos.payments.softDelete(record.id),
    );
    ref.invalidate(periodRefreshProvider);
    if (!deleted || !context.mounted) return;
    showUndoSnackbar(
      context,
      message: tr(
        'feed.deleted',
        namedArgs: <String, String>{'title': record.title},
      ),
      onUndo: () async {
        if (record.isIncome) {
          await repos.incomes.restore(record.id);
        } else {
          await repos.payments.restore(record.id);
        }
      },
    );
  }
}
