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

/// What a refresh changed, for the caller to report.
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

  /// Payments whose hand-picked period was merged away and which fell back to
  /// automatic binding. The UI says so once, rather than moving them silently
  /// (spec 5.3).
  final int reboundToAuto;

  bool get isEmpty =>
      periodsCreated == 0 &&
      periodsUpdated == 0 &&
      incomesMaterialised == 0 &&
      reboundToAuto == 0;
}

/// Keeps `budget_periods` and future `incomes` rows in step with the anchor
/// schedules of an income-driven Space (spec 4.7, 5.2).
///
/// Three rules shape everything here:
///
/// - **Closed periods are never recomputed.** A period closes when the next
///   anchor arrives, which is earlier than the freeze at `end_date + 14d`.
///   Once closed its boundaries are history (spec 5.4).
/// - **Open periods move in place.** The row keeps its id so a payment pinned
///   to it by hand still means what the user meant (spec 5.3).
/// - **Received rows are untouchable.** Neither a schedule change nor a
///   recompute may move an income already marked received (spec 5.4).
class PeriodService {
  PeriodService({
    required this.repos,
    required this.calendar,
    this.missingHolidayYears = const <int>{},
  });

  final Repositories repos;

  /// Weekends, public holidays and custom non-working days, already merged
  /// (spec 5.1.1). Resolving the three sources is the caller's job.
  final WorkingDayCalendar calendar;

  /// Years the holiday list could not be obtained for. A period anchored in
  /// one of them is written with `holiday_data_incomplete`, so the window can
  /// be narrowed later instead of silently standing as final (spec 5.1.1).
  final Set<int> missingHolidayYears;

  /// How many months of future occurrences each rule materialises when no
  /// period bounds them.
  static const int incomeHorizonMonths = PeriodMaterializer.horizonPeriods;

  /// The furthest [refresh] may be asked to reach, from today.
  static const int maxReachMonths = 24;

  /// How far each request to reach further goes.
  static const int horizonStepMonths = 3;

  /// Recomputes everything derivable from the schedules.
  ///
  /// Safe to call on every Space open: with no anchors it does nothing, which
  /// is the valid permanent state of a Space that has no income yet
  /// (spec 4.7).
  ///
  /// Periods run [PeriodMaterializer.horizonPeriods] ahead, further when
  /// [until] asks — the Feed scrolled to the end — and never less far than
  /// they already reach, so a horizon once extended is not taken back.
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
    // Grown in steps, so cut back to the reach: an edited schedule must not
    // ratchet the horizon out a step on every refresh.
    while (reach != null &&
        computed.length > PeriodMaterializer.horizonPeriods &&
        computed.last.startDate.isAfter(reach)) {
      computed.removeLast();
    }

    // One transaction for the whole refresh. Written row by row outside one,
    // every stream this feeds (incomes, periods, payments) re-emits after
    // each individual write, and every dependent provider recomputes that
    // many times over — which is what turned entering one regular income
    // into a visibly slow dashboard (spec 4.7 does not require this to be
    // instant, but there is no reason it shouldn't be).
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

  /// The day each period's anchor income actually arrived, where that is
  /// known (spec 5.4).
  ///
  /// A salary that came two days early means the days between belong to the
  /// cycle it opened, not to the one before: money spent on them came out of
  /// the new salary. So the receipt date, once confirmed, is the anchor —
  /// and because one cycle ends the day before the next begins, moving it
  /// carries the previous cycle's end along without a second rule.
  ///
  /// Only the cycle whose own anchor was confirmed moves. Later ones keep the
  /// dates the schedule computed: one early payment does not shift the
  /// timetable (spec 5.4).
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
      // Anchors that merged into one period share it; the earliest arrival is
      // the day the money started being available.
      final CalendarDate? held = byPeriod[periodId];
      if (held == null || actual.isBefore(held)) byPeriod[periodId] = actual;
    }
    return byPeriod;
  }

  /// Writes the computed boundaries over the open periods, in order.
  Future<({int created, int updated, int removed})> _syncPeriods({
    required Space space,
    required List<MaterializedPeriod> computed,
    required CalendarDate today,
    Map<String, CalendarDate> settled = const <String, CalendarDate>{},
  }) async {
    final List<BudgetPeriod> existing = await repos.periods.incomeDrivenIn(
      space.id,
    );

    // A period is closed once its end is behind us. Those are history and are
    // left exactly as they were.
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

    // The last day of history. An open period may not start before it, or the
    // two would overlap and a closed period would have to move to make room.
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

    /// Where period [i] actually begins: the confirmed receipt if there is
    /// one, otherwise the date the schedule computed.
    CalendarDate anchorOf(int i) {
      if (i >= computed.length) return computed.last.anchorDate;
      final CalendarDate scheduled = computed[i].anchorDate;
      if (i >= open.length) return scheduled;

      final CalendarDate? actual = settled[open[i].id];
      if (actual == null) return scheduled;
      // Never back into closed history.
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
        // One cycle ends the day before the next begins, so a settled anchor
        // pulls the previous cycle's end with it.
        final CalendarDate? end = i + 1 < computed.length
            ? anchorOf(i + 1).addDays(-1)
            : period.endDate;
        final bool moved = start != period.anchorDate;

        await repos.periods.updateBoundaries(
          open[i].id,
          startDate: start,
          endDate: end,
          anchorDate: start,
          // A confirmed receipt leaves nothing uncertain: the window collapses
          // onto the day it arrived.
          windowStart: moved ? start : period.windowStart,
          windowEnd: moved ? start : period.windowEnd,
          holidayDataIncomplete: moved ? false : _incomplete(period),
        );
        updated++;
      } else {
        await repos.periods.createIncomeDriven(
          spaceId: space.id,
          startDate: period.startDate,
          // The furthest period has no successor yet, so no end. It gets one
          // on the next refresh, when the horizon moves.
          endDate: period.endDate ?? period.startDate,
          anchorDate: period.anchorDate,
          windowStart: period.windowStart,
          windowEnd: period.windowEnd,
          holidayDataIncomplete: _incomplete(period),
        );
        created++;
      }
    }

    // Open rows past the end of the computed list no longer correspond to any
    // anchor — anchors merged, or a rule was removed.
    int removed = 0;
    for (int i = computed.length; i < open.length; i++) {
      await repos.periods.softDelete(open[i].id);
      removed++;
    }

    return (created: created, updated: updated, removed: removed);
  }

  /// Whether this period's window was computed without the holidays of the
  /// year it is anchored in.
  ///
  /// The window can only ever narrow when the data arrives — a holiday adds
  /// non-working days, never removes them — so the flag marks a window that is
  /// wide rather than one that is wrong (spec 5.1.1).
  bool _incomplete(MaterializedPeriod period) =>
      missingHolidayYears.contains(period.anchorDate.year);

  /// Where occurrences may exist: from the start of the cycle the user is in
  /// to the last known boundary.
  ///
  /// The floor is the cycle's start, not today. The anchor of the current
  /// period has usually already arrived — a Space created mid-month is the
  /// ordinary case — and without its row the period it opens has no amount
  /// and reads as uncomputable (spec 4.7). The horizon stops at the last
  /// boundary so every row has a period to belong to.
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

  /// The dates a rule's schedule puts an occurrence on, within the window.
  ///
  /// A schedule starts when it is written down: never earlier than the rule
  /// itself, or entering a salary today would invent last month's as well.
  /// History is not invented, and nothing lands past the last boundary.
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
    // Up to the last boundary; the months are counted only when none bounds
    // them.
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

  /// Fills in the future occurrences each rule is missing.
  ///
  /// Only gaps are filled: an occurrence that already exists keeps its own
  /// `is_paid`, note and any per-occurrence amount correction (spec 5.2).
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

  /// Lays a regular income's occurrences out again from its rule (spec 5.4).
  ///
  /// Within the occurrence window every unreceived row ends up on a scheduled
  /// date with the rule's title and amount: a deleted one comes back, an
  /// edited one is reset, one moved off its date is dropped and the date
  /// refilled. Received rows and rows in a frozen period stay as they are.
  /// Returns how many rows changed.
  ///
  /// This is the one way past a deletion: the gap-filling in [refresh] treats
  /// a deleted date as decided, and that is right for a single tap, not for
  /// a row lost by accident or a schedule edited back and forth.
  Future<int> regenerate(Space space, String ruleId, CalendarDate today) async {
    if (space.budgetMode != BudgetMode.incomeDriven) return 0;
    final IncomeRecurrenceRule? rule = await repos.incomeRules.byId(ruleId);
    final IncomeSchedule? schedule = rule == null ? null : scheduleOf(rule);
    if (rule == null || schedule == null) return 0;

    // The periods follow the rule's current schedule before anything is
    // laid out against them.
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

      // A received row holds its date; live rows are preferred over deleted
      // ones as the row a date keeps.
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
        if (await repos.incomes.freezeStateOf(row.id) == FreezeState.frozen) {
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

    // Fills the dates nothing held and binds the restored rows.
    final PeriodRefresh after = await refresh(space, today);
    return changed + after.incomesMaterialised;
  }

  /// Binds every record to the period its date falls in.
  ///
  /// Returns how many hand-pinned payments lost their period and fell back to
  /// automatic binding.
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

    // A manual pin survives a recompute, because the row it points at moved
    // rather than being replaced. It only breaks when that row is gone.
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
