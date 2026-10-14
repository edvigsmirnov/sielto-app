import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/synced_repository.dart';
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
    bool isClosed(BudgetPeriod p) =>
        p.endDate != null && p.endDate!.isBefore(today);

    final CalendarDate? closedThrough = existing
        .where(isClosed)
        .map((BudgetPeriod p) => p.endDate!)
        .fold<CalendarDate?>(
          null,
          (CalendarDate? a, CalendarDate b) =>
              a == null || a.isBefore(b) ? b : a,
        );

    final List<String> ids = <String>[
      for (final MaterializedPeriod p in computed)
        SyncedRepository.slotId('period:${space.id}:${p.slot}'),
    ];

    /// Confirmed receipt date, else the scheduled date.
    CalendarDate anchorOf(int i) {
      final CalendarDate scheduled = computed[i].anchorDate;
      final CalendarDate? actual = settled[ids[i]];
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
      final CalendarDate start = anchorOf(i);
      final CalendarDate? end = i + 1 < computed.length
          ? anchorOf(i + 1).addDays(-1)
          : period.endDate;
      final bool moved = start != period.anchorDate;
      // A confirmed receipt collapses the window onto its day.
      final CalendarDate windowStart = moved ? start : period.windowStart;
      final CalendarDate windowEnd = moved ? start : period.windowEnd;
      final bool incomplete = !moved && _incomplete(period);

      final BudgetPeriod? row = await repos.periods.anyById(ids[i]);
      if (row == null) {
        await repos.periods.createIncomeDriven(
          id: ids[i],
          generated: true,
          spaceId: space.id,
          startDate: start,
          // The last period has no successor yet.
          endDate: end ?? start,
          anchorDate: start,
          windowStart: windowStart,
          windowEnd: windowEnd,
          holidayDataIncomplete: incomplete,
        );
        created++;
        continue;
      }
      if (!row.isDeleted && isClosed(row)) continue;
      if (row.isDeleted) await repos.periods.restore(row.id);
      if (row.isDeleted ||
          row.startDate != start ||
          row.endDate != end ||
          row.anchorDate != start ||
          row.windowStart != windowStart ||
          row.windowEnd != windowEnd ||
          row.holidayDataIncomplete != incomplete) {
        await repos.periods.updateBoundaries(
          row.id,
          startDate: start,
          endDate: end,
          anchorDate: start,
          windowStart: windowStart,
          windowEnd: windowEnd,
          holidayDataIncomplete: incomplete,
        );
        updated++;
      }
    }

    // Open rows no slot asked for: anchors merged or a rule was removed.
    int removed = 0;
    for (final BudgetPeriod p in existing) {
      if (isClosed(p) || ids.contains(p.id)) continue;
      await repos.periods.softDelete(p.id);
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
  ({CalendarDate floor, List<({String id, CalendarDate date})> dates})
  _scheduledDates(
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

    final List<({String id, CalendarDate date})> dates =
        <({String id, CalendarDate date})>[];
    int year = floor.year;
    int month = floor.month;
    final int months = horizonEnd == null
        // One period per month.
        ? PeriodMaterializer.horizonPeriods
        : (horizonEnd.year - year) * 12 + horizonEnd.month - month + 1;
    for (int i = 0; i < months; i++) {
      final CalendarDate date = schedule
          .resolveFor(year, month, calendar: calendar)
          .anchorDate;
      if ((horizonEnd == null || !date.isAfter(horizonEnd)) &&
          !date.isBefore(floor)) {
        dates.add((id: incomeSlotId(rule.id, year, month), date: date));
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

      // A moved or deleted date still holds its month.
      final Set<String> filled = <String>{
        for (final Income i in await repos.incomes.occurrencesOf(rule.id)) i.id,
      };
      for (final ({String id, CalendarDate date}) slot in _scheduledDates(
        space,
        rule,
        schedule,
        from: from,
        horizonEnd: horizonEnd,
      ).dates) {
        if (!filled.add(slot.id)) continue;
        await repos.incomes.create(
          id: slot.id,
          generated: true,
          spaceId: space.id,
          title: rule.title,
          expectedDate: slot.date,
          amount: rule.amount,
          recurrenceRuleId: rule.id,
        );
        written++;
      }
    }
    return written;
  }

  /// The latest date of [schedule] on or before [today].
  CalendarDate lastDateOf(IncomeSchedule schedule, CalendarDate today) {
    final CalendarDate here = schedule
        .resolveFor(today.year, today.month, calendar: calendar)
        .anchorDate;
    if (!here.isAfter(today)) return here;
    final CalendarDate before = today.addMonths(-1);
    return schedule
        .resolveFor(before.year, before.month, calendar: calendar)
        .anchorDate;
  }

  /// Adds [rule]'s dates from [from] through [today], received before the
  /// current period; an anchor also gets those periods, closed.
  Future<void> backfill(
    Space space,
    IncomeRecurrenceRule rule, {
    required CalendarDate from,
    required CalendarDate today,
    required bool currentReceived,
  }) async {
    final IncomeSchedule? schedule = scheduleOf(rule);
    if (schedule == null || space.budgetMode != BudgetMode.incomeDriven) {
      return;
    }
    await refresh(space, today);
    final CalendarDate currentStart = (await _occurrenceWindow(
      space,
      today,
    )).from;

    await repos.db.transaction(() async {
      if (rule.isAnchor && from.isBefore(currentStart)) {
        final List<BudgetPeriod> existing = await repos.periods.incomeDrivenIn(
          space.id,
        );
        final List<MaterializedPeriod> past = PeriodMaterializer.materialize(
          anchors: <AnchorSchedule>[
            AnchorSchedule(ruleId: rule.id, schedule: schedule),
          ],
          from: from,
          calendar: calendar,
          count:
              (currentStart.year - from.year) * 12 +
              currentStart.month -
              from.month +
              2,
        );
        for (int i = 0; i < past.length; i++) {
          final MaterializedPeriod period = past[i];
          if (!period.startDate.isBefore(currentStart)) break;
          if (period.startDate.isBefore(from)) continue;
          final CalendarDate next = i + 1 < past.length
              ? past[i + 1].startDate
              : currentStart;
          final CalendarDate end =
              (next.isBefore(currentStart) ? next : currentStart).addDays(-1);
          final bool taken = existing.any(
            (BudgetPeriod p) =>
                !p.startDate.isAfter(end) &&
                (p.endDate == null || !p.endDate!.isBefore(period.startDate)),
          );
          final String id = SyncedRepository.slotId(
            'period:${space.id}:${period.slot}',
          );
          if (taken || await repos.periods.anyById(id) != null) continue;
          await repos.periods.createIncomeDriven(
            id: id,
            generated: true,
            spaceId: space.id,
            startDate: period.startDate,
            endDate: end,
            anchorDate: period.anchorDate,
            windowStart: period.windowStart,
            windowEnd: period.windowEnd,
            holidayDataIncomplete: _incomplete(period),
          );
        }
      }

      final Map<String, Income> filled = <String, Income>{
        for (final Income i in await repos.incomes.occurrencesOf(rule.id))
          i.id: i,
      };
      CalendarDate month = CalendarDate(from.year, from.month, 1);
      while (!month.isAfter(today)) {
        final String id = incomeSlotId(rule.id, month.year, month.month);
        final CalendarDate date = schedule
            .resolveFor(month.year, month.month, calendar: calendar)
            .anchorDate;
        month = month.addMonths(1);
        if (date.isBefore(from) || date.isAfter(today)) continue;
        final Income? row = filled[id];
        if (row != null) {
          if (!date.isBefore(currentStart) &&
              currentReceived &&
              !row.isDeleted &&
              !row.isPaid &&
              row.amount != null) {
            await repos.incomes.markReceived(row.id);
          }
          continue;
        }
        await repos.incomes.create(
          id: id,
          spaceId: space.id,
          title: rule.title,
          expectedDate: date,
          amount: rule.amount,
          recurrenceRuleId: rule.id,
          isPaid:
              rule.amount != null &&
              (date.isBefore(currentStart) || currentReceived),
        );
      }
    });
    await refresh(space, today);
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
      final ({CalendarDate floor, List<({String id, CalendarDate date})> dates})
      planned = _scheduledDates(
        space,
        rule,
        schedule,
        from: window.from,
        horizonEnd: window.horizonEnd,
      );
      final Map<String, CalendarDate> scheduled = <String, CalendarDate>{
        for (final ({String id, CalendarDate date}) slot in planned.dates)
          slot.id: slot.date,
      };

      int changed = 0;
      for (final Income row in await repos.incomes.occurrencesOf(ruleId)) {
        if (row.isPaid || row.expectedDate.isBefore(planned.floor)) continue;
        if (await repos.incomes.freezeStateOf(row) == FreezeState.frozen) {
          continue;
        }
        final CalendarDate? date = scheduled[row.id];
        if (date == null) {
          if (!row.isDeleted) {
            await repos.incomes.softDelete(row.id);
            changed++;
          }
          continue;
        }
        if (!row.isDeleted &&
            row.expectedDate == date &&
            row.title == rule.title &&
            row.amount == rule.amount) {
          continue;
        }
        if (row.isDeleted) await repos.incomes.restore(row.id);
        await repos.incomes.update(
          row.id,
          title: Value<String>(rule.title),
          amount: Value<Decimal?>(rule.amount),
          expectedDate: Value<CalendarDate>(date),
        );
        changed++;
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

/// One schedule month of one regular income, the same on every device.
String incomeSlotId(String ruleId, int year, int month) =>
    SyncedRepository.slotId('income:$ruleId:${scheduleMonth(year, month)}');
