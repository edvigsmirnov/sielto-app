import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/period/period_materializer.dart';
import 'package:sielto/domain/schedule/income_schedule.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/periods/schedule_mapping.dart';

@immutable
class PeriodRefresh {
  const PeriodRefresh({
    this.periodsCreated = 0,
    this.periodsUpdated = 0,
    this.incomesMaterialised = 0,
    this.reboundToAuto = 0,
  });

  final int periodsCreated;
  final int periodsUpdated;
  final int incomesMaterialised;

  /// Pinned payments whose period merged away and fell back to `auto`.
  final int reboundToAuto;

  bool get isEmpty =>
      periodsCreated == 0 &&
      periodsUpdated == 0 &&
      incomesMaterialised == 0 &&
      reboundToAuto == 0;
}

/// Closed periods are never recomputed; open ones update in place; received
/// incomes never move.
class PeriodService {
  PeriodService({
    required this.repos,
    required this.calendar,
    this.missingHolidayYears = const <int>{},
  });

  final Repositories repos;

  /// Weekends, holidays and custom days, already merged.
  final WorkingDayCalendar calendar;

  /// Periods anchored in these years get `holiday_data_incomplete`.
  final Set<int> missingHolidayYears;

  /// Months of occurrences when no period bounds them.
  static const int incomeHorizonMonths = PeriodMaterializer.horizonPeriods;

  /// Furthest [refresh] may reach, in months from today.
  static const int maxReachMonths = 24;

  /// Months per reach request.
  static const int horizonStepMonths = 3;

  /// Reaches [PeriodMaterializer.horizonPeriods] ahead or to [until], never
  /// less far than existing periods.
  Future<PeriodRefresh> refresh(
    Space space,
    CalendarDate today, {
    CalendarDate? until,
  }) async {
    if (space.budgetMode != BudgetMode.incomeDriven) {
      return const PeriodRefresh();
    }

    final List<IncomeRecurrenceRule> rules = await repos.incomeRules.inSpace(
      space.id,
    );
    final List<AnchorSchedule> anchors = <AnchorSchedule>[
      for (final IncomeRecurrenceRule rule in rules)
        if (rule.isAnchor)
          if (scheduleOf(rule) case final IncomeSchedule schedule)
            AnchorSchedule(ruleId: rule.id, schedule: schedule),
    ];
    if (anchors.isEmpty) return const PeriodRefresh();

    final CalendarDate cap = today.addMonths(maxReachMonths);
    CalendarDate? reach = until;
    for (final BudgetPeriod p in await repos.periods.incomeDrivenIn(space.id)) {
      if (reach == null || p.startDate.isAfter(reach)) reach = p.startDate;
    }
    if (reach != null && reach.isAfter(cap)) reach = cap;
    int count = PeriodMaterializer.horizonPeriods;
    List<MaterializedPeriod> computed;
    while (true) {
      computed = PeriodMaterializer.materialize(
        anchors: anchors,
        from: today,
        calendar: calendar,
        count: count,
      );
      if (reach == null ||
          computed.length < count ||
          !computed.last.startDate.isBefore(reach)) {
        break;
      }
      count += PeriodMaterializer.horizonPeriods;
    }
    // Trims the step overshoot.
    while (reach != null &&
        computed.length > PeriodMaterializer.horizonPeriods &&
        computed.last.startDate.isAfter(reach)) {
      computed.removeLast();
    }

    // One transaction, so dependent streams emit once.
    final ({
      ({int created, int removed, int updated}) periods,
      int materialised,
      int rebound,
    })
    result = await repos.db.transaction(() async {
      final ({int created, int removed, int updated}) periods =
          await _syncPeriods(
            space: space,
            computed: computed,
            today: today,
            settled: await _settledAnchors(space, rules),
          );
      final ({CalendarDate from, CalendarDate? horizonEnd}) window =
          await _occurrenceWindow(space, today);
      final int materialised = await _materialiseIncomes(
        space: space,
        rules: rules,
        from: window.from,
        horizonEnd: window.horizonEnd,
      );
      final int rebound = await _bindRecords(space);
      return (periods: periods, materialised: materialised, rebound: rebound);
    });
    final ({int created, int removed, int updated}) periods = result.periods;
    final int materialised = result.materialised;
    final int rebound = result.rebound;

    return PeriodRefresh(
      periodsCreated: periods.created,
      periodsUpdated: periods.updated,
      incomesMaterialised: materialised,
      reboundToAuto: rebound,
    );
  }

  /// Actual receipt date of each period's anchor, where confirmed. It becomes
  /// that period's start; later periods keep their scheduled dates.
  Future<Map<String, CalendarDate>> _settledAnchors(
    Space space,
    List<IncomeRecurrenceRule> rules,
  ) async {
    final Set<String> anchorRuleIds = <String>{
      for (final IncomeRecurrenceRule r in rules)
        if (r.isAnchor) r.id,
    };
    if (anchorRuleIds.isEmpty) return const <String, CalendarDate>{};

    final Map<String, CalendarDate> byPeriod = <String, CalendarDate>{};
    for (final Income income in await repos.incomes.inSpace(space.id)) {
      final String? periodId = income.budgetPeriodId;
      final CalendarDate? actual = income.actualDate;
      if (periodId == null || actual == null || !income.isPaid) continue;
      if (!anchorRuleIds.contains(income.recurrenceRuleId)) continue;
      // Merged anchors: the earliest arrival wins.
      final CalendarDate? held = byPeriod[periodId];
      if (held == null || actual.isBefore(held)) byPeriod[periodId] = actual;
    }
    return byPeriod;
  }

  Future<({int created, int updated, int removed})> _syncPeriods({
    required Space space,
    required List<MaterializedPeriod> computed,
    required CalendarDate today,
    Map<String, CalendarDate> settled = const <String, CalendarDate>{},
  }) async {
    final List<BudgetPeriod> existing = await repos.periods.incomeDrivenIn(
      space.id,
    );

    // Periods that ended before today are closed and left alone.
    final List<BudgetPeriod> open =
        existing
            .where(
              (BudgetPeriod p) =>
                  p.endDate == null || !p.endDate!.isBefore(today),
            )
            .toList()
          ..sort(
            (BudgetPeriod a, BudgetPeriod b) =>
                a.startDate.compareTo(b.startDate),
          );

    final CalendarDate? closedThrough = existing
        .where(
          (BudgetPeriod p) => p.endDate != null && p.endDate!.isBefore(today),
        )
        .map((BudgetPeriod p) => p.endDate!)
        .fold<CalendarDate?>(
          null,
          (CalendarDate? a, CalendarDate b) =>
              a == null || a.isBefore(b) ? b : a,
        );

    /// Confirmed receipt date, else the scheduled date.
    CalendarDate anchorOf(int i) {
      if (i >= computed.length) return computed.last.anchorDate;
      final CalendarDate scheduled = computed[i].anchorDate;
      if (i >= open.length) return scheduled;

      final CalendarDate? actual = settled[open[i].id];
      if (actual == null) return scheduled;
      if (closedThrough != null && !actual.isAfter(closedThrough)) {
        return closedThrough.addDays(1);
      }
      return actual;
    }

    int created = 0;
    int updated = 0;

    for (int i = 0; i < computed.length; i++) {
      final MaterializedPeriod period = computed[i];
      if (i < open.length) {
        final CalendarDate start = anchorOf(i);
        final CalendarDate? end = i + 1 < computed.length
            ? anchorOf(i + 1).addDays(-1)
            : period.endDate;
        final bool moved = start != period.anchorDate;

        await repos.periods.updateBoundaries(
          open[i].id,
          startDate: start,
          endDate: end,
          anchorDate: start,
          // A confirmed receipt collapses the window onto its day.
          windowStart: moved ? start : period.windowStart,
          windowEnd: moved ? start : period.windowEnd,
          holidayDataIncomplete: moved ? false : _incomplete(period),
        );
        updated++;
      } else {
        await repos.periods.createIncomeDriven(
          spaceId: space.id,
          startDate: period.startDate,
          // The last period has no successor yet.
          endDate: period.endDate ?? period.startDate,
          anchorDate: period.anchorDate,
          windowStart: period.windowStart,
          windowEnd: period.windowEnd,
          holidayDataIncomplete: _incomplete(period),
        );
        created++;
      }
    }

    // Open rows beyond the computed list: anchors merged or a rule was removed.
    int removed = 0;
    for (int i = computed.length; i < open.length; i++) {
      await repos.periods.softDelete(open[i].id);
      removed++;
    }

    return (created: created, updated: updated, removed: removed);
  }

  /// Whether the window was computed without that year's holidays.
  bool _incomplete(MaterializedPeriod period) =>
      missingHolidayYears.contains(period.anchorDate.year);

  /// From the current cycle's start to the last boundary.
  Future<({CalendarDate from, CalendarDate? horizonEnd})> _occurrenceWindow(
    Space space,
    CalendarDate today,
  ) async {
    final List<BudgetPeriod> boundaries = await repos.periods.incomeDrivenIn(
      space.id,
    );
    final BudgetPeriod? current = boundaries
        .where(
          (BudgetPeriod p) =>
              !p.startDate.isAfter(today) &&
              (p.endDate == null || !p.endDate!.isBefore(today)),
        )
        .firstOrNull;
    return (
      from: current?.startDate ?? today,
      horizonEnd: boundaries.isEmpty ? null : boundaries.last.endDate,
    );
  }

  /// Scheduled dates within the window, never before the rule was created.
  ({CalendarDate floor, List<CalendarDate> dates}) _scheduledDates(
    Space space,
    IncomeRecurrenceRule rule,
    IncomeSchedule schedule, {
    required CalendarDate from,
    required CalendarDate? horizonEnd,
  }) {
    final CalendarDate ruleStart = repos.spaces
        .clockFor(space)
        .dateOf(rule.createdAt);
    final CalendarDate floor = ruleStart.isAfter(from) ? ruleStart : from;

    final List<CalendarDate> dates = <CalendarDate>[];
    int year = floor.year;
    int month = floor.month;
    final int months = horizonEnd == null
        ? incomeHorizonMonths
        : (horizonEnd.year - year) * 12 + horizonEnd.month - month + 1;
    for (int i = 0; i < months; i++) {
      final CalendarDate date = schedule
          .resolveFor(year, month, calendar: calendar)
          .anchorDate;
      if ((horizonEnd == null || !date.isAfter(horizonEnd)) &&
          !date.isBefore(floor)) {
        dates.add(date);
      }
      month++;
      if (month == 13) {
        month = 1;
        year++;
      }
    }
    return (floor: floor, dates: dates);
  }

  /// Fills missing occurrences; existing ones keep their edits.
  Future<int> _materialiseIncomes({
    required Space space,
    required List<IncomeRecurrenceRule> rules,
    required CalendarDate from,
    required CalendarDate? horizonEnd,
  }) async {
    int written = 0;
    for (final IncomeRecurrenceRule rule in rules) {
      final IncomeSchedule? schedule = scheduleOf(rule);
      if (schedule == null) continue;

      final Set<String> already = await repos.incomes.materialisedDatesFor(
        rule.id,
      );
      for (final CalendarDate date in _scheduledDates(
        space,
        rule,
        schedule,
        from: from,
        horizonEnd: horizonEnd,
      ).dates) {
        if (!already.add(date.toIso())) continue;
        await repos.incomes.create(
          spaceId: space.id,
          title: rule.title,
          expectedDate: date,
          amount: rule.amount,
          recurrenceRuleId: rule.id,
        );
        written++;
      }
    }
    return written;
  }

  /// Resets unreceived, unfrozen occurrences to the schedule. Returns the
  /// number of rows changed.
  Future<int> regenerate(Space space, String ruleId, CalendarDate today) async {
    if (space.budgetMode != BudgetMode.incomeDriven) return 0;
    final IncomeRecurrenceRule? rule = await repos.incomeRules.byId(ruleId);
    final IncomeSchedule? schedule = rule == null ? null : scheduleOf(rule);
    if (rule == null || schedule == null) return 0;

    await refresh(space, today);

    final int changed = await repos.db.transaction(() async {
      final ({CalendarDate from, CalendarDate? horizonEnd}) window =
          await _occurrenceWindow(space, today);
      final ({CalendarDate floor, List<CalendarDate> dates}) planned =
          _scheduledDates(
            space,
            rule,
            schedule,
            from: window.from,
            horizonEnd: window.horizonEnd,
          );
      final Set<String> scheduled = <String>{
        for (final CalendarDate date in planned.dates) date.toIso(),
      };

      // Received rows first keep their date, then live rows before deleted ones.
      final List<Income> rows = await repos.incomes.occurrencesOf(ruleId)
        ..sort(
          (Income a, Income b) =>
              (a.isDeleted ? 1 : 0).compareTo(b.isDeleted ? 1 : 0),
        );
      final Set<String> held = <String>{
        for (final Income r in rows)
          if (r.isPaid && !r.isDeleted) r.expectedDate.toIso(),
      };

      int changed = 0;
      for (final Income row in rows) {
        if (row.isPaid || row.expectedDate.isBefore(planned.floor)) continue;
        final String iso = row.expectedDate.toIso();
        if (await repos.incomes.freezeStateOf(row) == FreezeState.frozen) {
          if (!row.isDeleted) held.add(iso);
          continue;
        }

        if (scheduled.contains(iso) && held.add(iso)) {
          if (row.isDeleted) await repos.incomes.restore(row.id);
          if (row.title != rule.title || row.amount != rule.amount) {
            await repos.incomes.update(
              row.id,
              title: Value<String>(rule.title),
              amount: Value<Decimal?>(rule.amount),
            );
          }
          if (row.isDeleted ||
              row.title != rule.title ||
              row.amount != rule.amount) {
            changed++;
          }
        } else if (!row.isDeleted) {
          await repos.incomes.softDelete(row.id);
          changed++;
        }
      }
      return changed;
    });

    // Fills the remaining dates and binds the rows.
    final PeriodRefresh after = await refresh(space, today);
    return changed + after.incomesMaterialised;
  }

  /// Binds records to periods by date. Returns how many pinned payments fell
  /// back to `auto`.
  Future<int> _bindRecords(Space space) async {
    final List<BudgetPeriod> periods = await repos.periods.incomeDrivenIn(
      space.id,
    );
    if (periods.isEmpty) return 0;

    String? periodFor(CalendarDate date) {
      for (final BudgetPeriod p in periods) {
        if (p.startDate.isAfter(date)) continue;
        final CalendarDate? end = p.endDate;
        if (end == null || !end.isBefore(date)) return p.id;
      }
      return null;
    }

    for (final Payment payment in await repos.payments.autoAssignedIn(
      space.id,
    )) {
      final String? target = periodFor(payment.dueDate);
      if (target != payment.budgetPeriodId) {
        await repos.payments.setPeriod(payment.id, target);
      }
    }

    // A pin breaks only when its period is gone.
    final Set<String> live = <String>{
      for (final BudgetPeriod p in periods) p.id,
    };
    int rebound = 0;
    for (final Payment payment in await repos.payments.manuallyAssignedIn(
      space.id,
    )) {
      final String? pinned = payment.budgetPeriodId;
      if (pinned != null && live.contains(pinned)) continue;
      await repos.payments.setPeriod(
        payment.id,
        periodFor(payment.dueDate),
        assignment: PeriodAssignment.auto,
      );
      rebound++;
    }

    for (final Income income in await repos.incomes.inSpace(space.id)) {
      final String? target = periodFor(income.expectedDate);
      if (target != income.budgetPeriodId) {
        await repos.incomes.setPeriod(income.id, target);
      }
    }

    return rebound;
  }
}
